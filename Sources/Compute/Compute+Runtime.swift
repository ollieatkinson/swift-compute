import _JSON
import Brain
import Foundation

extension Compute {
    public struct Thought: Codable, Hashable, Sendable {
        public enum Kind: String, Codable, Hashable, Sendable {
            case compute
            case returns
            case defaultValue
            case error
        }

        public let route: Compute.Route
        public let depth: Int
        public let keyword: String
        public let kind: Kind
        public let input: JSON?
        public let output: JSON?
        public let error: JSONError?
        public let state: JSON?

        public init(
            route: Compute.Route,
            depth: Int,
            keyword: String,
            kind: Kind = .compute,
            input: JSON? = nil,
            output: JSON? = nil,
            error: JSONError? = nil,
            state: JSON? = nil
        ) {
            self.route = route
            self.depth = depth
            self.keyword = keyword
            self.kind = kind
            self.input = input
            self.output = output
            self.error = error
            self.state = state
        }
    }

    public struct Step: Sendable, Equatable {
        public let state: JSON
        public let thoughts: [Thought]
        public let remainingThoughts: Int

        public var isThinking: Bool {
            remainingThoughts > 0
        }

        public init(state: JSON, thoughts: [Thought], remainingThoughts: Int) {
            self.state = state
            self.thoughts = thoughts
            self.remainingThoughts = remainingThoughts
        }
    }
}

extension Compute {
    enum Lemma: Hashable, Sendable {
        case source(Compute.Route)
        case route(Compute.Route)
        case dependency(Compute.Dependency)
    }

    enum Signal: Equatable, Sendable {
        /// Authored route input; evaluation settles the current observation demand.
        case pending(JSON)
        case value(JSON, projections: [Route: Outcome] = [:])
        case failure(JSONError, projections: [Route: Outcome] = [:])

        var projections: [Route: Outcome] {
            switch self {
            case .pending: [:]
            case .value(_, let projections), .failure(_, let projections): projections
            }
        }

        var value: JSON? {
            switch self {
            case .pending(let value), .value(let value, _): value
            case .failure: nil
            }
        }
    }
}

private struct RouteContinuation: Sendable {
    let tracing: Bool
    let receive: @Sendable (Compute.Outcome) -> Void
    let finish: @Sendable () -> Void
    var last: Compute.Outcome?
}

extension Compute {
    public actor Runtime: Sendable {
        private typealias ComputeBrain = Brain<Compute.Lemma, Compute.Signal>

        private struct Graph: Sendable {
            let concepts: [ComputeBrain.Concept]
            let state: ComputeBrain.State
            let change: ComputeBrain.State
            let routeConcepts: Set<Compute.Route>
        }

        private let document: JSON
        private let context: Compute.Context?
        private let initialDepth: Int
        private let functions: [String: any AnyReturnsKeyword]
        private let brain: ComputeBrain
        private var routeConcepts: Set<Compute.Route>
        // The compiled graph can briefly differ from requested observations
        // while a whole-document read or a newer live evaluation is in flight.
        private var graphDemand: Set<Compute.Route>?
        private var routeDependencies: [Compute.Route: Set<Compute.Dependency>] = [:]
        private var latestThoughts: [Compute.Thought] = []
        private var results: [Compute.Dependency: Result<JSON, JSONError>] = [:]
        private var subscriptions: [Compute.Dependency: Task<Void, Never>] = [:]
        private var referenceWaiters: [Compute.Dependency: [UUID: AsyncStream<Result<JSON, JSONError>>.Continuation]] = [:]
        private var observedRoutes: Set<Compute.Route> = []
        private var routeContinuations: [Compute.Route: [UUID: RouteContinuation]] = [:]
        private var evaluationVersion: UInt64 = 0
        // A newer completion supersedes an older completion; starting async work
        // does not block or suppress the last completed value.
        private var finishedEvaluationVersion: UInt64 = 0
        private var cancelledThroughVersion: UInt64 = 0
        private var dependencyVersions: [Compute.Route: UInt64] = [:]
        private var dependencyGraphVersion: UInt64 = 0
        private var dependencyGraphNeedsUpdate = false
        private var liveEvaluation: Task<Void, Never>?
        private var liveEvaluationVersion: UInt64 = 0
        private var liveChanges: ComputeBrain.State = [:]
        private var liveReset = false

        public init(
            document: JSON,
            context: Compute.Context? = nil,
            depth: Int = 0,
            functions: [any AnyReturnsKeyword] = [],
            computer: Computer = .default
        ) {
            let computer = computer.merging(functions)
            let graph = Self.graph(
                document: document,
                functions: computer.functions,
                routeDependencies: [:]
            )
            self.document = document
            self.context = context
            self.initialDepth = max(0, depth)
            self.functions = computer.functions
            self.routeConcepts = graph.routeConcepts
            self.brain = ComputeBrain(
                graph.concepts,
                state: graph.state,
                change: graph.change,
                remainingThoughts: { state in
                    Self.remainingThoughtCount(in: state)
                }
            )
        }

        deinit {
            liveEvaluation?.cancel()
            for subscription in subscriptions.values {
                subscription.cancel()
            }
        }

        public func value() async throws -> JSON {
            (try await settle(subscribe: false, reset: graphDemand != nil)).state
        }

        public func decode<Value: Decodable>(_ type: Value.Type = Value.self) async throws -> Value {
            try await value().decode(Value.self)
        }

        public func value(at route: Compute.Route) async throws -> JSON? {
            (try await value()).value(at: route.components)
        }

        public func decode<Value: Decodable>(
            _ type: Value.Type = Value.self,
            at route: Compute.Route
        ) async throws -> Value? {
            try await value(at: route)?.decode(Value.self)
        }

        @discardableResult
        public func step(_ count: Int = 1) async throws -> Compute.Step {
            let version = beginEvaluation()
            let graph: Graph?
            if graphDemand != nil {
                let full = Self.graph(
                    document: document,
                    functions: functions,
                    routeDependencies: routeDependencies
                )
                graphDemand = nil
                routeConcepts = full.routeConcepts
                graph = full
            } else { graph = nil }
            let runtime = functionRuntime()
            let commit: BrainCommit<Compute.Lemma, Compute.Signal>
            if let graph {
                commit = try await brain.commit(
                    resetTo: graph.state,
                    concepts: graph.concepts,
                    staging: graph.change,
                    thoughts: count,
                    thinking: thinking(with: runtime)
                )
            } else {
                commit = try await brain.commit(thoughts: count, thinking: thinking(with: runtime))
            }
            return try await finish(commit, runtime: runtime, subscribe: false, publishWhenSettled: true, version: version)
        }

        public nonisolated func run(at route: Compute.Route = .root) -> AsyncStream<Result<JSON, JSONError>> {
            stream(at: route, tracing: false) { $0.result }
        }

        /// Captures each selected result with its own immutable runtime evidence.
        /// Untraced and traced observers share the same graph and subscriptions.
        public nonisolated func run(
            at route: Compute.Route = .root,
            tracing: Bool
        ) -> AsyncStream<(result: Result<JSON, JSONError>, thoughts: [Compute.Thought])> {
            stream(at: route, tracing: tracing) { ($0.result, $0.thoughts) }
        }

        private nonisolated func stream<Value: Sendable>(
            at route: Compute.Route,
            tracing: Bool,
            project: @escaping @Sendable (Compute.Outcome) -> Value
        ) -> AsyncStream<Value> {
            AsyncStream { continuation in
                let id = UUID()
                let sink = RouteContinuation(tracing: tracing,
                    receive: { continuation.yield(project($0)) },
                    finish: { continuation.finish() })
                let task = Task { await addRouteContinuation(sink, id: id, route: route) }
                continuation.onTermination = { @Sendable [weak self] _ in
                    task.cancel()
                    Task { [weak self] in
                        guard let self else { return }
                        await self.removeRouteContinuation(id: id, route: route)
                    }
                }
            }
        }

        public var remainingThoughtCount: Int {
            get async {
                await brain.remainingThoughtCount
            }
        }

        public var isThinking: Bool {
            get async {
                await brain.isThinking
            }
        }

        private func addRouteContinuation(
            _ continuation: RouteContinuation,
            id: UUID,
            route: Compute.Route
        ) async {
            guard !Task.isCancelled else { return }
            routeContinuations[route, default: [:]][id] = continuation
            observedRoutes.insert(route)
            let selected = route.resolvingIndices(in: document)
            if route != .root, !document.conceptRoutes().contains(where: {
                $0.isPrefix(of: selected) || selected.isPrefix(of: $0)
            }) {
                if let value = document.value(at: route.components) {
                    yield(.success(value), to: route)
                } else { yield(.failure(JSONError("Missing value", path: route.path)), to: route) }
            }
            startLiveEvaluation(reset: true)
        }

        private func removeRouteContinuation(id: UUID, route: Compute.Route) {
            routeContinuations[route]?[id] = nil
            guard routeContinuations[route]?.isEmpty == true else { return }
            routeContinuations[route] = nil
            observedRoutes.remove(route)
            if observedRoutes.isEmpty { cancelSubscriptionsIfIdle() }
            else { startLiveEvaluation(reset: true) }
        }

        @discardableResult
        private func settle(
            subscribe: Bool,
            reset: Bool = false,
            version: UInt64? = nil,
            observing demand: Set<Compute.Route>? = nil
        ) async throws -> Compute
            .Step {
            let version = version ?? beginEvaluation()
            let graph: Graph?
            if reset {
                let resetGraph = Self.graph(
                    document: document,
                    functions: functions,
                    routeDependencies: routeDependencies,
                    observing: demand
                )
                graphDemand = demand
                routeConcepts = resetGraph.routeConcepts
                graph = resetGraph
            } else {
                graph = nil
            }
            let runtime = functionRuntime(liveVersion: subscribe ? version : nil)
            let thinking = thinking(with: runtime, liveVersion: subscribe ? version : nil)
            let commit: BrainCommit<Compute.Lemma, Compute.Signal>
            do {
                if let graph {
                    commit = try await brain.settle(
                        resetTo: graph.state,
                        concepts: graph.concepts,
                        staging: graph.change,
                        thinking: thinking
                    )
                } else {
                    commit = try await brain.settle(thinking: thinking)
                }
            } catch {
                // An initial failed read still identifies a live dependency.
                // Keep observing it so a later value can recover this runtime.
                await synchronizeDependencies(runtime: runtime, subscribe: subscribe, version: version)
                if error is CancellationError { throw error }
                if case BrainError.thoughtLimitExceeded = error {
                    throw Compute.Error.recursionLimitExceeded
                }
                throw JSONError(error)
            }
            return try await finish(
                commit,
                runtime: runtime,
                subscribe: subscribe,
                publishWhenSettled: true,
                version: version
            )
        }

        public var thoughts: [Compute.Thought] {
            latestThoughts
        }

        private func beginEvaluation() -> UInt64 {
            evaluationVersion &+= 1
            return evaluationVersion
        }

        private func finish(
            _ commit: BrainCommit<Compute.Lemma, Compute.Signal>,
            runtime: Compute.FunctionRuntime,
            subscribe: Bool,
            publishWhenSettled: Bool,
            version: UInt64
        ) async throws -> Compute.Step {
            let thoughts = await runtime.takeThoughts()
            // Live route failures remain native signals until projection.
            // Recorded errors can also describe handled explain/fallback work.
            let snapshot = try materialize(commit.state)
            let step = Compute.Step(
                state: snapshot.value,
                thoughts: thoughts,
                remainingThoughts: commit.remainingThoughts
            )
            await synchronizeDependencies(runtime: runtime, subscribe: subscribe, version: version)
            guard version > cancelledThroughVersion, version >= finishedEvaluationVersion,
                !Task.isCancelled else { return step }
            finishedEvaluationVersion = version
            if !thoughts.isEmpty { latestThoughts = thoughts }
            if publishWhenSettled, !step.isThinking {
                publish(step.state, failures: snapshot.failures, projections: snapshot.projections)
            }
            if !subscribe, let failure = snapshot.failures.first { throw failure.error }
            return step
        }

        private func synchronizeDependencies(runtime: Compute.FunctionRuntime, subscribe: Bool, version: UInt64) async {
            let (tracked, resolved) = await runtime.dependencySnapshot()
            guard version > cancelledThroughVersion, !Task.isCancelled else { return }
            let changed = merge(tracked, version: version)
            // Prime the read-to-observe handoff before starting subjects. A
            // delayed initial replay must not replace a newer one-shot read
            // performed merely because that dependency had not been cached.
            for (route, dependencies) in tracked where dependencyVersions[route] == version {
                for dependency in dependencies where results[dependency] == nil {
                    if let result = resolved[dependency] { results[dependency] = result }
                }
            }
            if changed { dependencyGraphNeedsUpdate = true }
            await updateDependencyGraph()
            if version > cancelledThroughVersion, !Task.isCancelled, subscribe || !observedRoutes.isEmpty {
                let active = routeDependencies.filter { owner, _ in
                    observedRoutes.contains {
                        let selected = $0.resolvingIndices(in: document)
                        return selected.isPrefix(of: owner) || owner.isPrefix(of: selected)
                    }
                }
                resubscribe(to: Array(active.values.flatMap { $0 }))
            }
        }

        private func updateDependencyGraph() async {
            guard dependencyGraphNeedsUpdate else { return }
            dependencyGraphNeedsUpdate = false
            let graph = Self.graph(document: document, functions: functions,
                                   routeDependencies: routeDependencies, observing: graphDemand)
            routeConcepts = graph.routeConcepts
            dependencyGraphVersion &+= 1
            await brain.update(concepts: graph.concepts, version: dependencyGraphVersion)
        }

        /// Observe a resolved input before evaluating the expression it returned.
        /// Otherwise a pending descendant prevents its parent from ever going live.
        private func resolved(
            _ result: Result<JSON, JSONError>,
            dependency: Compute.Dependency,
            route: Compute.Route,
            version: UInt64
        ) {
            guard track(dependency, at: route, version: version) else { return }
            if results[dependency] == nil { results[dependency] = result }
            subscribe(to: dependency)
        }

        private func track(
            _ dependency: Compute.Dependency,
            at route: Compute.Route,
            version: UInt64
        ) -> Bool {
            guard version == liveEvaluationVersion, version > cancelledThroughVersion,
                version >= dependencyVersions[route, default: 0], !Task.isCancelled else { return false }
            dependencyVersions[route] = version
            if routeDependencies[route, default: []].insert(dependency).inserted {
                dependencyGraphNeedsUpdate = true
            }
            return true
        }

        /// A live From uses the same subscription for its initial value and all
        /// later changes. A separate snapshot would release and reopen providers
        /// with zero grace, and could miss a change during that handoff.
        private func referenceValue(
            for dependency: Compute.Dependency,
            at route: Compute.Route,
            version: UInt64
        ) async throws -> JSON {
            guard track(dependency, at: route, version: version) else { throw CancellationError() }
            if let result = results[dependency] { return try result.get() }
            let (values, continuation) = AsyncStream.makeStream(of: Result<JSON, JSONError>.self)
            let id = UUID()
            referenceWaiters[dependency, default: [:]][id] = continuation
            continuation.onTermination = { @Sendable [weak self] _ in
                Task { await self?.removeReferenceWaiter(id, for: dependency) }
            }
            subscribe(to: dependency)
            var iterator = values.makeAsyncIterator()
            guard let result = await iterator.next() else {
                try Task.checkCancellation()
                throw JSONError("Reference source finished without a value")
            }
            try Task.checkCancellation()
            return try result.get()
        }

        private func removeReferenceWaiter(_ id: UUID, for dependency: Compute.Dependency) {
            referenceWaiters[dependency]?[id] = nil
            if referenceWaiters[dependency]?.isEmpty == true { referenceWaiters[dependency] = nil }
        }

        private func finishReferenceWaiters(for dependency: Compute.Dependency) {
            guard let waiters = referenceWaiters.removeValue(forKey: dependency) else { return }
            for continuation in waiters.values {
                continuation.finish()
            }
        }

        private func merge(_ tracked: [Compute.Route: Set<Compute.Dependency>], version: UInt64) -> Bool {
            var changed = false
            for (route, dependencies) in tracked {
                // Independent routes may finish in either order. Only a newer
                // evaluation of this same route supersedes its dependencies.
                guard version >= dependencyVersions[route, default: 0] else { continue }
                dependencyVersions[route] = version
                let old = routeDependencies[route] ?? []
                if dependencies != old {
                    routeDependencies[route] = dependencies.isEmpty ? nil : dependencies
                    changed = true
                }
            }
            return changed
        }

        private func resubscribe(to dependencies: [Compute.Dependency]) {
            let next = Set(dependencies)
            for (dependency, task) in subscriptions where !next.contains(dependency) {
                task.cancel()
                subscriptions[dependency] = nil
                results[dependency] = nil
                finishReferenceWaiters(for: dependency)
            }
            for dependency in next where subscriptions[dependency] == nil {
                subscribe(to: dependency)
            }
        }

        private func subscribe(to dependency: Compute.Dependency) {
            guard subscriptions[dependency] == nil,
                let function = functions[dependency.keyword] as? any Compute.ReturnsKeywordDefinition else { return }
            let frame = Compute.Frame(
                context: context ?? Compute.Context(),
                runtime: functionRuntime(),
                route: .root,
                depth: dependency.depth,
                references: []
            )
            subscriptions[dependency] = Task { [weak self] in
                for await result in function.subject(data: dependency.data, frame: frame, bufferingPolicy: .unbounded) {
                    if Task.isCancelled { return }
                    guard let self else { return }
                    await self.apply(result, to: dependency)
                }
                if !Task.isCancelled { await self?.finishReferenceWaiters(for: dependency) }
            }
        }

        private func cancelSubscriptionsIfIdle() {
            guard observedRoutes.isEmpty else { return }
            liveEvaluation?.cancel()
            liveEvaluation = nil
            liveChanges.removeAll()
            liveReset = false
            for (dependency, subscription) in subscriptions {
                subscription.cancel()
                results[dependency] = nil
                finishReferenceWaiters(for: dependency)
            }
            subscriptions.removeAll()
        }

        private func apply(_ result: Result<JSON, JSONError>, to dependency: Compute.Dependency) async {
            // Cancellation can occur between the source's check and this actor hop.
            guard !Task.isCancelled, subscriptions[dependency] != nil else { return }
            let initial = results[dependency] == nil
            let waiters = referenceWaiters.removeValue(forKey: dependency)
            if let waiters {
                for continuation in waiters.values {
                    continuation.yield(result)
                    continuation.finish()
                }
            }
            guard results[dependency] != result else { return }
            results[dependency] = result
            // Complete the wave already waiting for this first snapshot. A later
            // emission replaces that wave even when a descendant is still pending.
            if initial, waiters?.isEmpty == false { return }
            let signal: Compute.Signal
            switch result {
            case .success(let value):
                signal = .value(value)
            case .failure(let error):
                signal = .failure(error)
            }
            startLiveEvaluation(staging: [.dependency(dependency): signal])
        }

        private func startLiveEvaluation(reset: Bool = false, staging changes: ComputeBrain.State = [:]) {
            liveEvaluation?.cancel()
            liveChanges.merge(changes) { _, new in new }
            liveReset = liveReset || reset
            let version = beginEvaluation()
            liveEvaluationVersion = version
            liveEvaluation = Task { [weak self] in
                guard let self else { return }
                await self.evaluateLive(version: version)
            }
        }

        private func evaluateLive(version: UInt64) async {
            do {
                try Task.checkCancellation()
                await updateDependencyGraph()
                try Task.checkCancellation()
                let changes = liveChanges
                liveChanges.removeAll(keepingCapacity: true)
                await brain.stage(changes)
                try Task.checkCancellation()
                let reset = liveReset || graphDemand != observedRoutes
                try await settle(
                    subscribe: true,
                    reset: reset,
                    version: version,
                    observing: observedRoutes
                )
                if version == liveEvaluationVersion { liveReset = false }
            } catch {
                if error is CancellationError, version == liveEvaluationVersion,
                    version < evaluationVersion, !Task.isCancelled, !observedRoutes.isEmpty {
                    // A newer one-shot read can acquire the Brain gate before
                    // this queued live wave and supersede its dependency owner.
                    // Resume with that owner's inputs instead of publishing the
                    // internal cancellation as a field failure.
                    startLiveEvaluation(reset: true)
                } else if version == liveEvaluationVersion, version > cancelledThroughVersion,
                    version >= finishedEvaluationVersion, !Task.isCancelled {
                    finishedEvaluationVersion = version
                    publishFailure(JSONError(error))
                }
            }
            if version == liveEvaluationVersion { liveEvaluation = nil }
        }

        private func publishFailure(_ error: JSONError) {
            for route in observedRoutes {
                yield(.failure(error), to: route)
            }
        }

        public func cancel() async {
            evaluationVersion &+= 1
            cancelledThroughVersion = evaluationVersion
            let runningEvaluation = liveEvaluation
            liveEvaluation?.cancel()
            liveEvaluation = nil
            liveChanges.removeAll()
            liveReset = false
            let running = Array(subscriptions.values)
            for subscription in subscriptions.values {
                subscription.cancel()
            }
            for dependency in Array(referenceWaiters.keys) { finishReferenceWaiters(for: dependency) }
            subscriptions.removeAll()
            results.removeAll()
            observedRoutes.removeAll()
            for continuations in routeContinuations.values {
                for routeContinuation in continuations.values {
                    routeContinuation.finish()
                }
            }
            routeContinuations.removeAll()
            await brain.cancelStreams()
            for task in running {
                await task.value
            }
            await runningEvaluation?.value
        }

        private func publish(
            _ state: JSON,
            failures: [(route: Compute.Route, error: JSONError)],
            projections: [Compute.Route: Compute.Outcome]
        ) {
            for route in Array(routeContinuations.keys) {
                let selected = route.resolvingIndices(in: document)
                if let projected = projections[route] {
                    yield(projected, to: route)
                    continue
                }
                let result: Result<JSON, JSONError>
                if let failure = failures.first(where: {
                    $0.route.isPrefix(of: selected) || selected.isPrefix(of: $0.route)
                }) {
                    result = .failure(failure.error)
                } else if let value = state.value(at: route.components) {
                    result = .success(value)
                } else {
                    result = .failure(JSONError("Missing value", path: route.path))
                }
                let thoughts = projections.filter { entry in
                    routeConcepts.contains(entry.key)
                        && (entry.key.isPrefix(of: selected) || selected.isPrefix(of: entry.key))
                }.sorted { $0.key.path.lexicographicallyPrecedes($1.key.path) }
                    .flatMap { $0.value.thoughts }
                yield(Compute.Outcome(result: result, thoughts: thoughts), to: route)
            }
        }

        /// Only the completed computation and its descendants are ready here.
        /// Aggregate/container observations wait for the atomic Brain commit.
        private func publish(_ signal: Compute.Signal, at route: Compute.Route, version: UInt64) {
            guard version == liveEvaluationVersion, version > cancelledThroughVersion,
                  !Task.isCancelled else { return }
            for observed in observedRoutes where observed != .root {
                let selected = observed.resolvingIndices(in: document)
                guard route.isPrefix(of: selected) else { continue }
                if let projected = signal.projections[observed] {
                    yield(projected, to: observed)
                    continue
                }
                switch signal {
                case .pending: break
                case .failure(let error, _): yield(.failure(error), to: observed, thoughts: signal.projections[route]?.thoughts ?? [])
                case .value(let value, _):
                    let path = Array(selected.components.dropFirst(route.components.count))
                    if let selected = value.value(at: path) {
                        yield(.success(selected), to: observed, thoughts: signal.projections[route]?.thoughts ?? [])
                    } else {
                        yield(.failure(JSONError("Missing value", path: observed.path)), to: observed, thoughts: signal.projections[route]?.thoughts ?? [])
                    }
                }
            }
        }

        private func publishProjection(_ result: Compute.Outcome, to route: Compute.Route, version: UInt64) {
            guard version == liveEvaluationVersion, version > cancelledThroughVersion,
                  !Task.isCancelled, route != .root, observedRoutes.contains(route) else { return }
            yield(result, to: route)
        }

        private func yield(_ result: Result<JSON, JSONError>, to route: Compute.Route, thoughts: [Compute.Thought] = []) {
            yield(Compute.Outcome(result: result, thoughts: thoughts), to: route)
        }

        private func yield(_ outcome: Compute.Outcome, to route: Compute.Route) {
            guard var continuations = routeContinuations[route] else { return }
            for id in continuations.keys {
                let output = continuations[id]?.tracing == true ? outcome : Compute.Outcome(result: outcome.result)
                guard continuations[id]?.last != output else { continue }
                continuations[id]?.last = output
                continuations[id]?.receive(output)
            }
            routeContinuations[route] = continuations
        }

        private func functionRuntime(liveVersion: UInt64? = nil) -> Compute.FunctionRuntime {
            let routes = routeConcepts
            let didResolve: Compute.FunctionRuntime.Resolved?
            let referenceValue: Compute.FunctionRuntime.ReferenceValue?
            if let version = liveVersion {
                didResolve = { [weak self] route, dependency, result in
                    await self?.resolved(result, dependency: dependency, route: route, version: version)
                }
                referenceValue = { [weak self] route, dependency in
                    guard let self else { throw CancellationError() }
                    return try await self.referenceValue(for: dependency, at: route, version: version)
                }
            } else {
                didResolve = nil
                referenceValue = nil
            }
            let didProject: Compute.FunctionRuntime.Projected?
            if let version = liveVersion {
                didProject = { [weak self] route, result in
                    await self?.publishProjection(result, to: route, version: version)
                }
            } else {
                didProject = nil
            }
            // A one-shot read still evaluates the whole document while retaining
            // the field outcomes needed by observers already following this graph.
            let observing = liveVersion == nil ? observedRoutes.union([.root]) : observedRoutes
            let projection = observedRoutes.isEmpty ? nil
                : Compute.Projection(observing: observing, document: document)
            return Compute.FunctionRuntime(functions: functions, results: results,
                dependencyOwner: { route in route.nearestAncestor(in: routes) ?? route },
                didResolve: didResolve, referenceValue: referenceValue,
                projection: projection, didProject: didProject,
                tracing: routeContinuations.values.contains { $0.values.contains { $0.tracing } })
        }

        private func thinking(
            with runtime: Compute.FunctionRuntime,
            liveVersion: UInt64? = nil
        ) -> ComputeBrain.Thinking {
            let context = context ?? Compute.Context()
            return { lemma, state in
                guard case .route(let route) = lemma else { return nil }
                let signal: Compute.Signal?
                do {
                    signal = try await self.evaluate(
                        route,
                        state: state,
                        runtime: runtime,
                        context: context
                    )
                } catch {
                    try Task.checkCancellation()
                    guard liveVersion != nil, !(error is CancellationError) else { throw error }
                    signal = .failure(JSONError(error), projections: await runtime.projectionResults(at: route, result: .failure(JSONError(error))))
                }
                if let liveVersion, let signal {
                    await self.publish(signal, at: route, version: liveVersion)
                }
                return signal
            }
        }

        private func evaluate(
            _ route: Compute.Route,
            state: ComputeBrain.State,
            runtime: Compute.FunctionRuntime,
            context: Compute.Context
        ) async throws -> Compute.Signal? {
            let current = try document(from: state, excluding: route, at: route)
            guard let object = current.object else {
                return nil
            }
            await runtime.trackDependencies(for: route, state: state)
            let step = try await Self.evaluate(object, at: route, runtime: runtime, context: context,
                depth: initialDepth)
            try Task.checkCancellation()
            var nextState = state
            nextState[.route(route)] = .value(step.output)
            let nextDocument = try document(from: nextState)
            await runtime.record(
                Compute.Thought(
                    route: route,
                    depth: initialDepth,
                    keyword: step.keyword,
                    kind: step.kind,
                    // A retained nested stage is still an invocation in its
                    // caller's trace. Top-level graph steps keep their fragment.
                    input: initialDepth > 0 && step.kind != .defaultValue
                        ? .object(["{returns}": step.input]) : step.input,
                    output: step.output,
                    state: nextDocument
                ), output: route)
            return .value(step.output, projections: await runtime.projectionResults(at: route, result: .success(step.output)))
        }

        private static func evaluate(
            _ object: [String: JSON],
            at route: Compute.Route,
            runtime: Compute.FunctionRuntime,
            context: Compute.Context,
            depth: Int
        ) async throws -> (keyword: String, kind: Compute.Thought.Kind, input: JSON, output: JSON) {
            if let invocation = Compute.Invocation(object: object) {
                guard depth < 20 else { throw Compute.Error.recursionLimitExceeded }
                let functionRoute = route["{returns}", .key(invocation.keyword)]
                do {
                    if let output = try await runtime.compute(
                        keyword: invocation.keyword,
                        data: invocation.data,
                        in: Compute.Frame(context: context, runtime: runtime,
                            route: functionRoute, depth: depth, references: [], output: route),
                        recordThought: false,
                        projecting: invocation.default == nil ? route : nil
                    ) {
                        return (
                            invocation.keyword, await runtime.kind(for: invocation.keyword),
                            invocation.json, output
                        )
                    }
                    guard let fallback = invocation.default else {
                        return (
                            invocation.keyword, await runtime.kind(for: invocation.keyword),
                            invocation.json, .null
                        )
                    }
                    return try await defaultValue(fallback, at: route, runtime: runtime, context: context, depth: depth)
                } catch {
                    guard let fallback = invocation.default else {
                        throw error
                    }
                    return try await defaultValue(fallback, at: route, runtime: runtime, context: context, depth: depth)
                }
            }
            throw JSONError("Unsupported compute object", path: route.path)
        }

        private static func defaultValue(
            _ fallback: JSON,
            at route: Compute.Route,
            runtime: Compute.FunctionRuntime,
            context: Compute.Context,
            depth: Int
        ) async throws -> (keyword: String, kind: Compute.Thought.Kind, input: JSON, output: JSON) {
            let output = try await fallback.compute(
                in: Compute.Frame(
                    context: context,
                    runtime: runtime,
                    route: route["default"],
                    depth: depth,
                    references: [],
                    output: route
                ))
            return ("default", .defaultValue, fallback, output)
        }

        private static func graph(
            document: JSON,
            functions: [String: any AnyReturnsKeyword],
            routeDependencies: [Compute.Route: Set<Compute.Dependency>],
            observing demand: Set<Compute.Route>? = nil
        ) -> Graph {
            let demand = demand.map { Set($0.map { $0.resolvingIndices(in: document) }) }
            let routes = document.conceptRoutes()
                .filter { route in
                    demand?.contains { $0.isPrefix(of: route) || route.isPrefix(of: $0) } ?? true
                }
                .sortedForComputeEvaluation()
            let routeConcepts = Set(routes)
            var state: ComputeBrain.State = [:]
            var change: ComputeBrain.State = [:]
            var concepts: [ComputeBrain.Concept] = []

            for route in routes {
                guard let value = document.value(at: route.components) else { continue }
                state[.route(route)] = .pending(value)
                state[.source(route)] = .value(value)
                change[.source(route)] = .value(value)
                concepts.append(
                    ComputeBrain.Concept(
                        .route(route),
                        inputs: inputs(
                            for: route,
                            value: value,
                            functions: functions,
                            routeConcepts: routeConcepts,
                            routeDependencies: routeDependencies
                        )
                    ))
            }
            return Graph(concepts: concepts, state: state, change: change, routeConcepts: routeConcepts)
        }

        private static func inputs(
            for route: Compute.Route,
            value: JSON,
            functions: [String: any AnyReturnsKeyword],
            routeConcepts: Set<Compute.Route>,
            routeDependencies: [Compute.Route: Set<Compute.Dependency>]
        ) -> Set<Compute.Lemma> {
            var inputs: Set<Compute.Lemma> = []
            if let object = value.object, let invocation = Compute.Invocation(object: object) {
                if functions[invocation.keyword] != nil {
                    inputs.insert(.source(route))
                } else {
                    let children = route.directChildConcepts(in: routeConcepts)
                    if children.isEmpty {
                        inputs.insert(.source(route))
                    } else {
                        inputs.formUnion(children.map { .route($0) })
                    }
                }
            } else {
                inputs.insert(.source(route))
            }
            inputs.formUnion((routeDependencies[route] ?? []).map(Compute.Lemma.dependency))
            return inputs
        }

        private static func remainingThoughtCount(in state: ComputeBrain.State) -> Int {
            state.reduce(0) { count, entry in
                guard case .route = entry.key else { return count }
                guard case .pending = entry.value else { return count }
                return count + 1
            }
        }

        private func document(
            from state: ComputeBrain.State,
            excluding excluded: Compute.Route? = nil,
            at root: Compute.Route = .root
        ) throws -> JSON {
            try materialize(state, excluding: excluded, at: root).value
        }

        private func materialize(
            _ state: ComputeBrain.State,
            excluding excluded: Compute.Route? = nil,
            at root: Compute.Route = .root
        ) throws
            -> (value: JSON, failures: [(route: Compute.Route, error: JSONError)],
                projections: [Compute.Route: Compute.Outcome]) {
            // An operation consumes only its own input branch. Final values and
            // diagnostic snapshots still request the entire document.
            var output = root == .root ? document : document.value(at: root.components) ?? .null
            var failures: [(route: Compute.Route, error: JSONError)] = []
            var projections: [Compute.Route: Compute.Outcome] = [:]
            var finalAncestors: [Compute.Route] = []
            let routeValues = state.compactMap { entry -> (Compute.Route, Compute.Signal)? in
                guard case .route(let route) = entry.key else { return nil }
                guard root.isPrefix(of: route) else { return nil }
                guard !route.isExcluded(from: excluded) else { return nil }
                return (route, entry.value)
            }.sorted { lhs, rhs in
                if lhs.0.components.count != rhs.0.components.count {
                    return lhs.0.components.count < rhs.0.components.count
                }
                return lhs.0.components.lexicographicallyPrecedes(rhs.0.components) {
                    $0.stringValue < $1.stringValue
                }
            }
            for (route, signal) in routeValues {
                guard !finalAncestors.contains(where: { $0.isPrefix(of: route) }) else { continue }
                projections.merge(signal.projections) { _, current in current }
                let destination = root == .root ? route
                    : Compute.Route(Array(route.components.dropFirst(root.components.count)))
                switch signal {
                case .pending(let value):
                    try output.set(value, at: destination)
                case .value(let value, _):
                    try output.set(value, at: destination)
                    finalAncestors.append(route)
                case .failure(let error, _):
                    failures.append((route, error))
                    finalAncestors.append(route)
                }
            }
            return (output, failures, projections)
        }
    }
}

extension Compute {
    public struct Dependency: Sendable, Equatable, Hashable {
        public let keyword: String
        public let data: JSON
        public let depth: Int
    }
}

extension Compute {
    actor FunctionRuntime {
        typealias Resolved = @Sendable (Compute.Route, Compute.Dependency, Result<JSON, JSONError>) async -> Void
        typealias ReferenceValue = @Sendable (Compute.Route, Compute.Dependency) async throws -> JSON
        typealias Projected = @Sendable (Compute.Route, Compute.Outcome) async -> Void
        private let functions: [String: any AnyReturnsKeyword]
        private let results: [Compute.Dependency: Result<JSON, JSONError>]
        private let dependencyOwner: @Sendable (Compute.Route) -> Compute.Route
        private let didResolve: Resolved?
        private let referenceValue: ReferenceValue?
        private var projection: Compute.Projection?
        private let didProject: Projected?
        private let tracing: Bool
        private var recordedOutputs: [(output: Compute.Route, thought: Compute.Thought)] = []
        private var dependencyState: [Compute.Lemma: Compute.Signal] = [:]
        private var resolved: [Compute.Dependency: Result<JSON, JSONError>] = [:]
        private var tracked: [Compute.Route: Set<Compute.Dependency>] = [:]
        private var thoughts: [Compute.Thought] = []
        private var capturedThoughts: [UInt64: [Compute.Thought]] = [:]
        private var nextCapture: UInt64 = 0

        init(
            functions: [String: any AnyReturnsKeyword],
            results: [Compute.Dependency: Result<JSON, JSONError>],
            dependencyOwner: @escaping @Sendable (Compute.Route) -> Compute.Route,
            didResolve: Resolved? = nil,
            referenceValue: ReferenceValue? = nil,
            projection: Compute.Projection? = nil,
            didProject: Projected? = nil,
            tracing: Bool = false
        ) {
            self.functions = functions
            self.results = results
            self.dependencyOwner = dependencyOwner
            self.didResolve = didResolve
            self.referenceValue = referenceValue
            self.projection = projection
            self.didProject = didProject
            self.tracing = tracing
        }

        func compute(
            keyword: String,
            data: JSON,
            in frame: Compute.Frame,
            recordThought: Bool = true,
            projecting: Compute.Route? = nil
        ) async throws -> JSON? {
            try Task.checkCancellation()
            let context = frame.context
            let route = frame.route
            let depth = frame.depth
            let references = frame.references
            let captures = frame.captures
            guard let function = functions[keyword] else {
                throw JSONError("Unregistered Compute keyword \(keyword)", path: route.path)
            }
            var input: JSON
            if let function = function as? any Compute.ReturnsKeywordDefinition {
                input = try await function.request(data: data.compute(in: frame), frame: frame)
            } else {
                input = data
            }
            var outputReferences = references
            var outputContext = context
            if function is any ReferenceKeyword {
                let entered = try await following(
                    JSON.decoded(Compute.Keyword.From.self, from: input),
                    keyword: keyword,
                    in: frame,
                    item: context.item
                )
                let request = entered.references.last!.request
                // Effective bindings are also part of the subscription key.
                // Sibling uses of one template can address different entities.
                var effective: JSON.Object = ["reference": request.reference]
                if let context = request.context { effective["context"] = .object(context) }
                input = .object(effective)
                outputContext = entered.context
                outputReferences = entered.references
            }
            var rawOutput: JSON?
            var evaluated = false
            if function is any Compute.ReturnsKeywordDefinition {
                rawOutput = try await value(keyword: keyword, data: input, frame: frame)
            } else {
                rawOutput = try await function.compute(data: input, frame: frame)
            }
            // Provider evidence belongs to this read, before its returned
            // program executes. It is neither another operation nor user data.
            if !(function is any Compute.OpaqueOutputKeyword) {
                while let snapshot = rawOutput?.rawValue as? Compute.SourceSnapshot {
                    try Task.checkCancellation()
                    for thought in snapshot.thoughts {
                        record(thought, captures: captures, output: frame.output)
                    }
                    rawOutput = try snapshot.result.get()
                    if case .evaluated = snapshot {
                        evaluated = true
                        break
                    }
                }
            }
            let output: JSON?
            if function is any Compute.OpaqueOutputKeyword || evaluated {
                output = rawOutput
            } else {
                output = try await rawOutput?.compute(
                    in: Compute.Frame(
                        context: outputContext,
                        runtime: self,
                        route: route.computeObjectRoute(for: keyword),
                        depth: depth + 1,
                        references: outputReferences,
                        captures: captures,
                        output: frame.output
                    ), projecting: projecting.flatMap { route in
                        projection?.includesDescendants(of: route) == true ? route : nil
                    }, publishing: false)
            }
            if recordThought, let output {
                let thoughtRoute = route.computeObjectRoute(for: keyword)
                record(
                    Compute.Thought(
                        route: thoughtRoute,
                        depth: depth + 1,
                        keyword: keyword,
                        kind: kind(for: keyword),
                        input: JSON.returns(keyword, data),
                        output: output
                    ), captures: captures, output: frame.output)
            }
            return output
        }

        func following(
            _ authored: Compute.Keyword.From,
            keyword: String,
            in frame: Compute.Frame,
            item: JSON?
        ) async throws -> Compute.Frame {
            guard let function = functions[keyword] as? any ReferenceKeyword else {
                throw JSONError("Not a reference provider: " + keyword, path: frame.route.path)
            }
            let authored = authored.scoped(to: frame.scope)
            let request = try await function.request(for: authored.reference, context: authored.context)
            var context = frame.context
            context.item = item
            if context.referenceContext != nil { context.referenceContext = request.context }
            let entry = (keyword: keyword, request: request, context: context)
            guard !frame.references.contains(where: {
                $0.keyword == keyword && $0.request == request && $0.context == context
            }) else {
                let chain = (frame.references + [entry]).map { $0.request.diagnosticName }.joined(separator: " -> ")
                throw JSONError("Reference cycle: " + chain, path: frame.route.path)
            }
            return Compute.Frame(context: context, runtime: self, route: frame.route,
                depth: frame.depth + 1, references: frame.references + [entry],
                captures: frame.captures, output: frame.output)
        }

        func capture(
            in frame: Compute.Frame,
            _ operation: @Sendable (Compute.Frame) async throws -> JSON
        ) async -> (result: Result<JSON, JSONError>, thoughts: [Compute.Thought]) {
            nextCapture &+= 1
            let id = nextCapture
            capturedThoughts[id] = []
            let capturedFrame = Compute.Frame(
                context: frame.context,
                runtime: frame.runtime,
                route: frame.route,
                depth: frame.depth,
                references: frame.references,
                captures: frame.captures + [id],
                output: frame.output
            )
            let result: Result<JSON, JSONError>
            do { result = .success(try await operation(capturedFrame)) }
            catch { result = .failure(JSONError(error)) }
            return (result, capturedThoughts.removeValue(forKey: id) ?? [])
        }

        /// A default one-shot subject replays the read already used to settle
        /// this dependency. Custom streaming subjects still open their source.
        func result(for dependency: Compute.Dependency) -> Result<JSON, JSONError>? {
            if let signal = dependencyState[.dependency(dependency)] {
                switch signal {
                case .pending(let value), .value(let value, _): return .success(value)
                case .failure(let error, _): return .failure(error)
                }
            }
            return results[dependency] ?? resolved[dependency]
        }

        func value(keyword: String, data: JSON, frame: Compute.Frame) async throws -> JSON? {
            guard let function = functions[keyword] else {
                throw JSONError("Unregistered Compute keyword \(keyword)", path: frame.route.path)
            }
            if function is any Compute.ReturnsKeywordDefinition {
                // Canonical reference input is independent of execution depth.
                // Its returned program still runs in each caller's own frame.
                let dependencyDepth = function is any ReferenceKeyword ? 0 : frame.depth
                let dependency = Compute.Dependency(
                    keyword: keyword,
                    data: data,
                    depth: dependencyDepth
                )
                let route = dependencyOwner(frame.route.computeObjectRoute(for: keyword))
                tracked[route, default: []].insert(dependency)
                if let result = results[dependency] {
                    // The Brain may have accepted a newer staged value since
                    // this evaluation captured its cache. Read the same state
                    // that triggered this route, rather than consuming its
                    // change with an older cached input.
                    let current: Result<JSON, JSONError>
                    if let signal = dependencyState[.dependency(dependency)] {
                        switch signal {
                        case .pending(let value), .value(let value, _): current = .success(value)
                        case .failure(let error, _): current = .failure(error)
                        }
                    } else { current = result }
                    await didResolve?(route, dependency, current)
                    return try current.get()
                }
                do {
                    let value: JSON?
                    if function is any ReferenceKeyword || function is any Compute.StreamingKeywordDefinition,
                       let referenceValue {
                        value = try await referenceValue(route, dependency)
                    } else {
                        value = try await function.compute(data: data, frame: frame)
                    }
                    if let value {
                        resolved[dependency] = .success(value)
                        await didResolve?(route, dependency, .success(value))
                    }
                    return value
                } catch {
                    resolved[dependency] = .failure(JSONError(error))
                    await didResolve?(route, dependency, .failure(JSONError(error)))
                    throw error
                }
            }
            return try await function.compute(data: data, frame: frame)
        }

        func includesProjection(_ route: Compute.Route) -> Bool {
            projection?.includes(route) ?? true
        }

        func projectsDescendants(of route: Compute.Route) -> Bool {
            projection?.includesDescendants(of: route) ?? false
        }

        func prepareProjection(_ value: JSON, at route: Compute.Route) async {
            let records = recordedOutputs
            for (observed, result) in projection?.prepare(value, at: route, thoughts: {
                Self.thoughts(in: $0, records: records)
            }) ?? [] {
                await didProject?(observed, result)
            }
        }

        func project(_ result: Result<JSON, JSONError>, at route: Compute.Route) async {
            let records = recordedOutputs
            for (observed, selected) in projection?.resolve(result, at: route, thoughts: {
                Self.thoughts(in: $0, records: records)
            }) ?? [] {
                await didProject?(observed, selected)
            }
        }

        func projectionResults(
            at route: Compute.Route,
            result: Result<JSON, JSONError>
        ) -> [Compute.Route: Compute.Outcome] {
            var outcomes = projection?.results(in: route) ?? [:]
            if tracing {
                outcomes[route] = Compute.Outcome(result: result,
                    thoughts: Self.thoughts(in: route, records: recordedOutputs))
            }
            return outcomes
        }

        private static func thoughts(
            in route: Compute.Route,
            records: [(output: Compute.Route, thought: Compute.Thought)]
        ) -> [Compute.Thought] {
            records.filter { $0.output.isPrefix(of: route) || route.isPrefix(of: $0.output) }
                .map(\.thought).sortedByRoute()
        }

        func trackDependencies(for route: Compute.Route, state: [Compute.Lemma: Compute.Signal]) {
            dependencyState = state
            if tracked[route] == nil {
                tracked[route] = []
            }
        }

        func registeredFunctions() -> [String: any AnyReturnsKeyword] {
            functions
        }

        func kind(for keyword: String) -> Compute.Thought.Kind {
            guard let function = functions[keyword] else { return .compute }
            return function is any Compute.ReturnsKeywordDefinition ? .returns : .compute
        }

        func dependencySnapshot() -> (
            tracked: [Compute.Route: Set<Compute.Dependency>],
            resolved: [Compute.Dependency: Result<JSON, JSONError>]
        ) {
            (tracked, resolved)
        }

        func record(
            _ thought: Compute.Thought,
            captures: [UInt64] = [],
            output: Compute.Route? = nil
        ) {
            thoughts.append(thought)
            if tracing, let output { recordedOutputs.append((output, thought)) }
            for id in captures { capturedThoughts[id]?.append(thought) }
        }

        func takeThoughts() -> [Compute.Thought] {
            defer { thoughts.removeAll(keepingCapacity: true) }
            return thoughts.sortedByRoute()
        }
    }
}

extension Compute.Route {
    fileprivate func computeObjectRoute(for keyword: String) -> Compute.Route {
        guard components.count >= 2 else { return self }
        guard components[components.count - 2] == .key("{returns}") else { return self }
        guard components[components.count - 1] == .key(keyword) else { return self }
        return Compute.Route(Array(components.dropLast(2)))
    }

    /// Resolve authored array indices while preserving indices inside computed
    /// output, whose shape is known only when that ancestor finishes.
    func resolvingIndices(in document: JSON) -> Compute.Route {
        var current = document
        var resolved: [Component] = []
        for (offset, component) in components.enumerated() {
            if let object = current.object, Compute.Invocation(object: object) != nil {
                return Compute.Route(resolved + components.dropFirst(offset))
            }
            switch component {
            case .index(let index):
                guard let array = current.array, let index = array.resolvedIndex(index) else {
                    return Compute.Route(resolved + components.dropFirst(offset))
                }
                resolved.append(.index(index))
                current = array[index]
            case .key(let key):
                resolved.append(component)
                current = current.object?[key] ?? .null
            }
        }
        return Compute.Route(resolved)
    }

    func isPrefix(of route: Compute.Route) -> Bool {
        guard components.count <= route.components.count else { return false }
        return zip(components, route.components).allSatisfy(==)
    }

    fileprivate func isExcluded(from excluded: Compute.Route?) -> Bool {
        guard let excluded else { return false }
        return self == excluded || isPrefix(of: excluded)
    }

    fileprivate func nearestAncestor(in routes: Set<Compute.Route>) -> Compute.Route? {
        var components = components
        while true {
            let route = Compute.Route(components)
            if routes.contains(route) {
                return route
            }
            guard !components.isEmpty else { return nil }
            components.removeLast()
        }
    }

    fileprivate func directChildConcepts(in routes: Set<Compute.Route>) -> [Compute.Route] {
        routes.filter { candidate in
            guard routeContains(candidate), candidate != self else { return false }
            var components = candidate.components
            while !components.isEmpty {
                components.removeLast()
                let ancestor = Compute.Route(components)
                guard ancestor != self else { return true }
                if routes.contains(ancestor) {
                    return false
                }
            }
            return false
        }
        .sortedForComputeEvaluation()
    }

    private func routeContains(_ route: Compute.Route) -> Bool {
        guard components.count < route.components.count else { return false }
        return zip(components, route.components).allSatisfy(==)
    }
}

extension Array where Element == Compute.Route {
    fileprivate func sortedForComputeEvaluation() -> [Compute.Route] {
        sorted { lhs, rhs in
            if lhs.components.count != rhs.components.count {
                return lhs.components.count > rhs.components.count
            }
            return lhs.components.lexicographicallyPrecedes(rhs.components) {
                $0.stringValue < $1.stringValue
            }
        }
    }
}

extension Array where Element == Compute.Thought {
    fileprivate func sortedByRoute() -> [Compute.Thought] {
        sorted { lhs, rhs in
            if lhs.route.components.count != rhs.route.components.count {
                return lhs.route.components.count > rhs.route.components.count
            }
            return lhs.route.components.lexicographicallyPrecedes(rhs.route.components) {
                $0.stringValue < $1.stringValue
            }
        }
    }
}
