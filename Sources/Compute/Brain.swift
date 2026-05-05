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
    private var observers: [Lemma: Set<Lemma>]
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
        change.merge(changes) { _, new in new }
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
            change.merge(stagedChanges) { _, new in new }
        }

        latestThoughts.removeAll(keepingCapacity: true)
        let initialChange = change
        var writes = change
        change.removeAll(keepingCapacity: true)
        if !writes.isEmpty {
            state.merge(writes) { _, new in new }
        }

        var waves = 0
        var remainingLimit = limit ?? .max
        while maxThoughts.map({ waves < $0 }) ?? true {
            let affected = affected(by: writes)
            guard !affected.isEmpty else { break }
            guard remainingLimit > 0 else {
                self.change = writes
                throw BrainError.thoughtLimitExceeded
            }
            remainingLimit -= 1

            var thoughts: State = [:]
            for lemma in affected {
                guard let signal = try await thinking(lemma, state) else { continue }
                guard state[lemma] != signal else { continue }
                thoughts[lemma] = signal
            }
            guard !thoughts.isEmpty else { break }

            state.merge(thoughts) { _, new in new }
            latestThoughts.merge(thoughts) { _, new in new }
            writes = thoughts
            waves += 1
            remaining = countThoughts(state)
            publish(state)
        }

        remaining = countThoughts(state)
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
    }

    private func affected(by changes: State) -> [Lemma] {
        let affected = changes.keys.reduce(into: Set<Lemma>()) { affected, lemma in
            affected.formUnion(observers[lemma] ?? [])
        }
        return conceptOrder.filter { affected.contains($0) }
    }

    private static func observers(for concepts: [Concept]) -> [Lemma: Set<Lemma>] {
        concepts.reduce(into: [:]) { observers, concept in
            for input in concept.inputs {
                observers[input, default: []].insert(concept.lemma)
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
