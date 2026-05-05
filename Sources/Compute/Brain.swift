import Foundation

public enum BrainError: Error, Equatable, Sendable {
    case thoughtLimitExceeded
}

public struct BrainCommit<Lemma, Signal>: Sendable where Lemma: Hashable & Sendable, Signal: Equatable & Sendable {
    public typealias State = [Lemma: Signal]

    public let state: State
    public let change: State
    public let thoughts: State
    public let remainingThoughts: Int

    public var isThinking: Bool {
        remainingThoughts > 0
    }

    public init(state: State, change: State, thoughts: State, remainingThoughts: Int) {
        self.state = state
        self.change = change
        self.thoughts = thoughts
        self.remainingThoughts = remainingThoughts
    }
}

private actor BrainGate {
    private var isLocked = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func lock() async {
        if isLocked {
            await withCheckedContinuation { continuation in
                waiters.append(continuation)
            }
        } else {
            isLocked = true
        }
    }

    func unlock() {
        guard !waiters.isEmpty else {
            isLocked = false
            return
        }
        waiters.removeFirst().resume()
    }
}

public actor Brain<Lemma, Signal>: Sendable where Lemma: Hashable & Sendable, Signal: Equatable & Sendable {
    public typealias State = [Lemma: Signal]
    public typealias Thinking = @Sendable (_ lemma: Lemma, _ state: State) async throws -> Signal?
    public typealias ThoughtCounter = @Sendable (State) -> Int

    public struct Concept: Sendable, Equatable {
        public let lemma: Lemma
        public let inputs: Set<Lemma>

        public init(_ lemma: Lemma, inputs: Set<Lemma> = []) {
            self.lemma = lemma
            self.inputs = inputs
        }
    }

    private let countThoughts: ThoughtCounter
    private let gate = BrainGate()
    private var state: State
    private var change: State
    private var latestThoughts: State = [:]
    private var remaining: Int
    private var conceptOrder: [Lemma]
    private var observers: [Lemma: [Int]]
    private var affectedMarks: [Int]
    private var affectedGeneration = 0
    private var stateContinuations: [UUID: AsyncStream<State>.Continuation] = [:]

    public init(
        _ concepts: [Concept],
        state: State = [:],
        change: State = [:],
        remainingThoughts countThoughts: @escaping ThoughtCounter
    ) {
        self.countThoughts = countThoughts
        self.state = state
        self.change = change
        self.latestThoughts = [:]
        self.remaining = countThoughts(state)
        self.conceptOrder = concepts.map(\.lemma)
        self.observers = Self.observers(for: concepts)
        self.affectedMarks = Array(repeating: 0, count: concepts.count)
    }

    public var value: State {
        state
    }

    public var thoughts: State {
        latestThoughts
    }

    public var remainingThoughtCount: Int {
        remaining
    }

    public var isThinking: Bool {
        remaining > 0
    }

    public func stage(_ changes: State) async {
        await gate.lock()
        for (lemma, signal) in changes {
            change[lemma] = signal
        }
        await gate.unlock()
    }

    public func update(concepts: [Concept]) async {
        await gate.lock()
        setConcepts(concepts)
        await gate.unlock()
    }

    public func reset(to state: State, concepts: [Concept], staging changes: State = [:]) async {
        await gate.lock()
        resetUnlocked(to: state, concepts: concepts, staging: changes)
        await gate.unlock()
    }

    @discardableResult
    public func commit(thoughts count: Int = 1, thinking: Thinking) async throws -> BrainCommit<Lemma, Signal> {
        await gate.lock()
        do {
            let commit = try await think(maxThoughts: max(count, 0), thinking: thinking)
            await gate.unlock()
            return commit
        } catch {
            await gate.unlock()
            throw error
        }
    }

    @discardableResult
    public func commit(
        resetTo state: State,
        concepts: [Concept],
        staging changes: State = [:],
        thoughts count: Int = 1,
        thinking: Thinking
    ) async throws -> BrainCommit<Lemma, Signal> {
        await gate.lock()
        do {
            let commit = try await think(
                resetTo: state,
                concepts: concepts,
                staging: changes,
                maxThoughts: max(count, 0),
                thinking: thinking
            )
            await gate.unlock()
            return commit
        } catch {
            await gate.unlock()
            throw error
        }
    }

    @discardableResult
    public func settle(limit: Int = 1_000, thinking: Thinking) async throws -> BrainCommit<Lemma, Signal> {
        await gate.lock()
        do {
            let commit = try await think(limit: limit, thinking: thinking)
            await gate.unlock()
            return commit
        } catch {
            await gate.unlock()
            throw error
        }
    }

    @discardableResult
    public func settle(
        resetTo state: State,
        concepts: [Concept],
        staging changes: State = [:],
        limit: Int = 1_000,
        thinking: Thinking
    ) async throws -> BrainCommit<Lemma, Signal> {
        await gate.lock()
        do {
            let commit = try await think(
                resetTo: state,
                concepts: concepts,
                staging: changes,
                limit: limit,
                thinking: thinking
            )
            await gate.unlock()
            return commit
        } catch {
            await gate.unlock()
            throw error
        }
    }

    @discardableResult
    private func think(
        resetTo resetState: State? = nil,
        concepts resetConcepts: [Concept]? = nil,
        staging stagedChanges: State = [:],
        maxThoughts: Int? = nil,
        limit: Int? = nil,
        thinking: Thinking
    ) async throws -> BrainCommit<Lemma, Signal> {
        if let resetState, let resetConcepts {
            resetUnlocked(to: resetState, concepts: resetConcepts, staging: stagedChanges)
        } else if !stagedChanges.isEmpty {
            for (lemma, signal) in stagedChanges {
                change[lemma] = signal
            }
        }

        latestThoughts.removeAll(keepingCapacity: true)
        let initialChange = change
        var writes = change
        change.removeAll(keepingCapacity: true)
        if !writes.isEmpty {
            for (lemma, signal) in writes {
                state[lemma] = signal
            }
        }

        var waves = 0
        var remainingLimit = limit ?? .max
        while maxThoughts.map({ waves < $0 }) ?? true {
            let affectedProfile = ComputeProfiling.start()
            let affected = affected(by: writes)
            ComputeProfiling.record("brain.affected", since: affectedProfile)
            guard !affected.isEmpty else { break }
            guard remainingLimit > 0 else {
                self.change = writes
                throw BrainError.thoughtLimitExceeded
            }
            remainingLimit -= 1

            var thoughts: State = [:]
            let evaluateProfile = ComputeProfiling.start()
            do {
                for lemma in affected {
                    guard let signal = try await thinking(lemma, state) else { continue }
                    guard state[lemma] != signal else { continue }
                    thoughts[lemma] = signal
                }
                ComputeProfiling.record("brain.evaluateAffected", since: evaluateProfile)
            } catch {
                ComputeProfiling.record("brain.evaluateAffected", since: evaluateProfile)
                throw error
            }
            guard !thoughts.isEmpty else { break }

            let mergeProfile = ComputeProfiling.start()
            for (lemma, signal) in thoughts {
                state[lemma] = signal
                latestThoughts[lemma] = signal
            }
            ComputeProfiling.record("brain.mergeThoughts", since: mergeProfile)
            writes = thoughts
            waves += 1
            let countProfile = ComputeProfiling.start()
            remaining = countThoughts(state)
            ComputeProfiling.record("brain.countRemaining", since: countProfile)
            publish(state)
        }

        let countProfile = ComputeProfiling.start()
        remaining = countThoughts(state)
        ComputeProfiling.record("brain.countRemaining", since: countProfile)
        change = remaining > 0 ? writes : [:]
        return BrainCommit(
            state: state,
            change: initialChange,
            thoughts: latestThoughts,
            remainingThoughts: remaining
        )
    }

    private func resetUnlocked(to state: State, concepts: [Concept], staging changes: State) {
        let changed = self.state != state
        self.state = state
        self.change = changes
        latestThoughts.removeAll(keepingCapacity: true)
        remaining = countThoughts(state)
        setConcepts(concepts)
        if changed {
            publish(state)
        }
    }

    private func setConcepts(_ concepts: [Concept]) {
        conceptOrder = concepts.map(\.lemma)
        observers = Self.observers(for: concepts)
        affectedMarks = Array(repeating: 0, count: concepts.count)
        affectedGeneration = 0
    }

    private func affected(by changes: State) -> [Lemma] {
        if changes.count == 1,
           let lemma = changes.keys.first,
           let indexes = observers[lemma] {
            return indexes.map { conceptOrder[$0] }
        }

        affectedGeneration &+= 1
        if affectedGeneration == 0 {
            affectedMarks = Array(repeating: 0, count: conceptOrder.count)
            affectedGeneration = 1
        }
        let generation = affectedGeneration
        var lowerBound = conceptOrder.count
        var upperBound = -1

        for lemma in changes.keys {
            guard let indexes = observers[lemma] else { continue }
            for index in indexes where affectedMarks[index] != generation {
                affectedMarks[index] = generation
                lowerBound = min(lowerBound, index)
                upperBound = max(upperBound, index)
            }
        }

        guard upperBound >= 0 else {
            return []
        }
        var affected: [Lemma] = []
        affected.reserveCapacity(upperBound - lowerBound + 1)
        for index in lowerBound...upperBound where affectedMarks[index] == generation {
            affected.append(conceptOrder[index])
        }
        return affected
    }

    private static func observers(for concepts: [Concept]) -> [Lemma: [Int]] {
        concepts.enumerated().reduce(into: [:]) { observers, entry in
            let (index, concept) = entry
            for input in concept.inputs {
                observers[input, default: []].append(index)
            }
        }
    }

    public nonisolated func states() -> AsyncStream<State> {
        AsyncStream { continuation in
            let id = UUID()
            let task = Task {
                await addStateContinuation(continuation, id: id)
            }
            continuation.onTermination = { @Sendable [weak self] _ in
                task.cancel()
                Task { [weak self] in
                    await self?.removeStateContinuation(id: id)
                }
            }
        }
    }

    public func cancelStreams() {
        for continuation in stateContinuations.values {
            continuation.finish()
        }
        stateContinuations.removeAll()
    }

    private func addStateContinuation(_ continuation: AsyncStream<State>.Continuation, id: UUID) {
        stateContinuations[id] = continuation
        continuation.yield(state)
    }

    private func removeStateContinuation(id: UUID) {
        stateContinuations[id] = nil
    }

    private func publish(_ state: State) {
        for continuation in stateContinuations.values {
            continuation.yield(state)
        }
    }
}
