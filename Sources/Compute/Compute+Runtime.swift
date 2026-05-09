import _JSON
import Brain
import Foundation

extension Compute {
    public struct Thought: Codable, Equatable, Sendable {
        public enum Kind: String, Codable, Equatable, Sendable {
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
        case value(JSON)
        case failure(JSONError)

        var value: JSON? {
            guard case .value(let value) = self else { return nil }
            return value
        }
    }
}

private struct RouteContinuation {
    var continuation: AsyncStream<Result<JSON, JSONError>>.Continuation
    var last: Result<JSON, JSONError>?
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
        private let functions: [String: any AnyReturnsKeyword]
        private let brain: ComputeBrain
        private var routeConcepts: Set<Compute.Route>
        private var routeDependencies: [Compute.Route: Set<Compute.Dependency>] = [:]
        private var latestThoughts: [Compute.Thought] = []
        private var results: [Compute.Dependency: Result<JSON, JSONError>] = [:]
        private var subscriptions: [Compute.Dependency: Task<Void, Never>] = [:]
        private var observedRoutes: Set<Compute.Route> = []
        private var routeContinuations: [Compute.Route: [UUID: RouteContinuation]] = [:]

        public init(
            document: JSON,
            context: Compute.Context? = nil,
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
            for subscription in subscriptions.values {
                subscription.cancel()
            }
        }

        public func value() async throws -> JSON {
            (try await settle(subscribe: false)).state
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
            let runtime = functionRuntime()
            let commit = try await brain.commit(thoughts: count, thinking: thinking(with: runtime))
            return try await finish(commit, runtime: runtime, subscribe: false, publishWhenSettled: true)
        }

        public nonisolated func run(at route: Compute.Route = .root) -> AsyncStream<
            Result<JSON, JSONError>
        > {
            AsyncStream { continuation in
                let id = UUID()
                let task = Task { await addRouteContinuation(continuation, id: id, route: route) }
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
            _ continuation: AsyncStream<Result<JSON, JSONError>>.Continuation,
            id: UUID,
            route: Compute.Route
        ) async {
            routeContinuations[route, default: [:]][id] = RouteContinuation(continuation: continuation)
            observedRoutes.insert(route)
            do {
                try await settle(subscribe: true, reset: true)
            } catch {
                yield(.failure(JSONError(error)), to: route)
            }
        }

        private func removeRouteContinuation(id: UUID, route: Compute.Route) {
            routeContinuations[route]?[id] = nil
            if routeContinuations[route]?.isEmpty ?? false {
                routeContinuations[route] = nil
                observedRoutes.remove(route)
            }
            cancelSubscriptionsIfIdle()
        }

        @discardableResult
        private func settle(subscribe: Bool, reset: Bool = false) async throws -> Compute.Step {
            let graph: Graph?
            if reset {
                let resetGraph = Self.graph(
                    document: document,
                    functions: functions,
                    routeDependencies: routeDependencies
                )
                routeConcepts = resetGraph.routeConcepts
                graph = resetGraph
            } else {
                graph = nil
            }
            let runtime = functionRuntime()
            let commit: BrainCommit<Compute.Lemma, Compute.Signal>
            do {
                if let graph {
                    commit = try await brain.settle(
                        resetTo: graph.state,
                        concepts: graph.concepts,
                        staging: graph.change,
                        thinking: thinking(with: runtime)
                    )
                } else {
                    commit = try await brain.settle(thinking: thinking(with: runtime))
                }
            } catch BrainError.thoughtLimitExceeded {
                throw Compute.Error.recursionLimitExceeded
            } catch {
                throw JSONError(error)
            }
            return try await finish(
                commit, runtime: runtime, subscribe: subscribe, publishWhenSettled: true)
        }

        public var thoughts: [Compute.Thought] {
            latestThoughts
        }

        private func finish(
            _ commit: BrainCommit<Compute.Lemma, Compute.Signal>,
            runtime: Compute.FunctionRuntime,
            subscribe: Bool,
            publishWhenSettled: Bool
        ) async throws -> Compute.Step {
            latestThoughts = await runtime.takeThoughts()
            if let error = latestThoughts.compactMap(\.error).first {
                throw error
            }

            let state = try document(from: commit.state)
            let step = Compute.Step(
                state: state,
                thoughts: latestThoughts,
                remainingThoughts: commit.remainingThoughts
            )
            let tracked = await runtime.dependenciesByRoute()
            if merge(tracked) {
                let graph = Self.graph(
                    document: document,
                    functions: functions,
                    routeDependencies: routeDependencies
                )
                routeConcepts = graph.routeConcepts
                await brain.update(concepts: graph.concepts)
            }
            if subscribe || !observedRoutes.isEmpty {
                resubscribe(to: Array(routeDependencies.values.flatMap { $0 }))
            }
            if publishWhenSettled, !step.isThinking {
                publish(step.state)
            }
            return step
        }

        private func merge(_ tracked: [Compute.Route: Set<Compute.Dependency>]) -> Bool {
            var changed = false
            for (route, dependencies) in tracked {
                let old = routeDependencies[route] ?? []
                let next = old.union(dependencies)
                if next != old {
                    routeDependencies[route] = next
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
            }
            for dependency in next where subscriptions[dependency] == nil {
                guard let function = functions[dependency.keyword] as? any Compute.ReturnsKeywordDefinition else { continue }
                let frame = Compute.Frame(
                    context: context ?? Compute.Context(),
                    runtime: functionRuntime(),
                    route: .root,
                    depth: 0
                )
                subscriptions[dependency] = Task { [weak self] in
                    for await result in function.subject(data: dependency.argument, frame: frame, bufferingPolicy: .unbounded) {
                        if Task.isCancelled { return }
                        guard let self else { return }
                        await self.apply(result, to: dependency)
                    }
                }
            }
        }

        private func cancelSubscriptionsIfIdle() {
            guard observedRoutes.isEmpty else { return }
            for subscription in subscriptions.values {
                subscription.cancel()
            }
            subscriptions.removeAll()
        }

        private func apply(_ result: Result<JSON, JSONError>, to dependency: Compute.Dependency) async {
            results[dependency] = result
            let signal: Compute.Signal
            switch result {
            case .success(let value):
                signal = .value(value)
            case .failure(let error):
                signal = .failure(error)
            }
            await brain.stage([.dependency(dependency): signal])
            do {
                try await settle(subscribe: true)
            } catch {
                await publishFailure(JSONError(error))
            }
        }

        private func publishFailure(_ error: JSONError) async {
            for route in observedRoutes {
                yield(.failure(error), to: route)
            }
        }

        public func cancel() async {
            let running = Array(subscriptions.values)
            for subscription in subscriptions.values {
                subscription.cancel()
            }
            subscriptions.removeAll()
            observedRoutes.removeAll()
            for continuations in routeContinuations.values {
                for routeContinuation in continuations.values {
                    routeContinuation.continuation.finish()
                }
            }
            routeContinuations.removeAll()
            await brain.cancelStreams()
            for task in running {
                await task.value
            }
        }

        private func publish(_ state: JSON) {
            for route in Array(routeContinuations.keys) {
                let result: Result<JSON, JSONError>
                if let value = state.value(at: route.components) {
                    result = .success(value)
                } else {
                    result = .failure(JSONError("Missing value", path: route.path))
                }
                yield(result, to: route)
            }
        }

        private func yield(_ result: Result<JSON, JSONError>, to route: Compute.Route) {
            guard var continuations = routeContinuations[route] else { return }
            for id in continuations.keys {
                guard continuations[id]?.last != result else { continue }
                continuations[id]?.last = result
                continuations[id]?.continuation.yield(result)
            }
            routeContinuations[route] = continuations
        }

        private func functionRuntime() -> Compute.FunctionRuntime {
            let routes = routeConcepts
            return Compute.FunctionRuntime(functions: functions, results: results) { route in
                route.nearestAncestor(in: routes) ?? route
            }
        }

        private func thinking(with runtime: Compute.FunctionRuntime) -> ComputeBrain.Thinking {
            let context = context ?? Compute.Context()
            return { lemma, state in
                guard case .route(let route) = lemma else { return nil }
                return try await self.evaluate(route, state: state, runtime: runtime, context: context)
            }
        }

        private func evaluate(
            _ route: Compute.Route,
            state: ComputeBrain.State,
            runtime: Compute.FunctionRuntime,
            context: Compute.Context
        ) async throws -> Compute.Signal? {
            let current = try document(from: state, excluding: route)
            guard let object = current.value(at: route.components)?.object else {
                return nil
            }
            let step = try await Self.evaluate(object, at: route, runtime: runtime, context: context)
            var nextState = state
            nextState[.route(route)] = .value(step.output)
            let nextDocument = try document(from: nextState)
            await runtime.record(
                Compute.Thought(
                    route: route,
                    depth: route.components.count,
                    keyword: step.keyword,
                    kind: step.kind,
                    input: step.input,
                    output: step.output,
                    state: nextDocument
                ))
            return .value(step.output)
        }

        private static func evaluate(
            _ object: [String: JSON],
            at route: Compute.Route,
            runtime: Compute.FunctionRuntime,
            context: Compute.Context
        ) async throws -> (keyword: String, kind: Compute.Thought.Kind, input: JSON, output: JSON) {
            if let invocation = Compute.Invocation(object: object) {
                let functionRoute = route["{returns}", .key(invocation.keyword)]
                do {
                    if let output = try await runtime.compute(
                        keyword: invocation.keyword,
                        argument: invocation.argument,
                        context: context,
                        route: functionRoute,
                        depth: 0,
                        recordThought: false
                    ) {
                        return (
                            invocation.keyword, await runtime.kind(for: invocation.keyword),
                            invocation.json, output
                        )
                    }
                    guard let fallback = invocation.fallback else {
                        return (
                            invocation.keyword, await runtime.kind(for: invocation.keyword),
                            invocation.json, .null
                        )
                    }
                    return try await defaultValue(fallback, at: route, runtime: runtime, context: context)
                } catch {
                    guard let fallback = invocation.fallback else {
                        throw error
                    }
                    return try await defaultValue(fallback, at: route, runtime: runtime, context: context)
                }
            }
            throw JSONError("Unsupported compute object", path: route.path)
        }

        private static func defaultValue(
            _ fallback: JSON,
            at route: Compute.Route,
            runtime: Compute.FunctionRuntime,
            context: Compute.Context
        ) async throws -> (keyword: String, kind: Compute.Thought.Kind, input: JSON, output: JSON) {
            let output = try await fallback.compute(
                in: Compute.Frame(
                    context: context,
                    runtime: runtime,
                    route: route["default"],
                    depth: 0
                ))
            return ("default", .defaultValue, fallback, output)
        }

        private static func graph(
            document: JSON,
            functions: [String: any AnyReturnsKeyword],
            routeDependencies: [Compute.Route: Set<Compute.Dependency>]
        ) -> Graph {
            let routes = document.conceptRoutes(functions: functions)
                .sortedForComputeEvaluation()
            let routeConcepts = Set(routes)
            var state: ComputeBrain.State = [:]
            var change: ComputeBrain.State = [:]
            var concepts: [ComputeBrain.Concept] = []

            for route in routes {
                guard let value = document.value(at: route.components) else { continue }
                state[.route(route)] = .value(value)
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
                guard case .value(let value) = entry.value else { return count }
                return count + (value.isComputeInvocation ? 1 : 0)
            }
        }

        private func document(
            from state: ComputeBrain.State,
            excluding excluded: Compute.Route? = nil
        ) throws -> JSON {
            var output = document
            var finalAncestors: [Compute.Route] = []
            let routeValues = state.compactMap { entry -> (Compute.Route, JSON)? in
                guard case .route(let route) = entry.key else { return nil }
                guard !route.isExcluded(from: excluded) else { return nil }
                guard case .value(let value) = entry.value else { return nil }
                return (route, value)
            }.sorted { lhs, rhs in
                if lhs.0.components.count != rhs.0.components.count {
                    return lhs.0.components.count < rhs.0.components.count
                }
                return lhs.0.path.lexicographicallyPrecedes(rhs.0.path)
            }
            for (route, value) in routeValues {
                guard !finalAncestors.contains(where: { $0.isPrefix(of: route) }) else { continue }
                try output.set(value, at: route)
                if !value.isComputeInvocation {
                    finalAncestors.append(route)
                }
            }
            return output
        }
    }
}

extension Compute {
    public struct Dependency: Sendable, Equatable, Hashable {
        public let keyword: String
        public let argument: JSON
    }
}

extension Compute {
    actor FunctionRuntime {
        private let functions: [String: any AnyReturnsKeyword]
        private let results: [Compute.Dependency: Result<JSON, JSONError>]
        private let dependencyOwner: @Sendable (Compute.Route) -> Compute.Route
        private var tracked: [Compute.Route: Set<Compute.Dependency>] = [:]
        private var thoughts: [Compute.Thought] = []

        init(
            functions: [String: any AnyReturnsKeyword],
            results: [Compute.Dependency: Result<JSON, JSONError>],
            dependencyOwner: @escaping @Sendable (Compute.Route) -> Compute.Route
        ) {
            self.functions = functions
            self.results = results
            self.dependencyOwner = dependencyOwner
        }

        func compute(
            keyword: String,
            argument: JSON,
            context: Compute.Context,
            route: Compute.Route,
            depth: Int,
            recordThought: Bool = true
        ) async throws -> JSON? {
            guard let function = functions[keyword] else { return nil }
            let frame = Compute.Frame(context: context, runtime: self, route: route, depth: depth)
            let rawOutput: JSON?
            if function is any Compute.ReturnsKeywordDefinition {
                let computed = try await argument.compute(in: frame)
                rawOutput = try await value(keyword: keyword, argument: computed, frame: frame)
            } else {
                rawOutput = try await function.compute(data: argument, frame: frame)
            }
            let output = try await rawOutput?.compute(
                in: Compute.Frame(
                    context: context,
                    runtime: self,
                    route: route.computeObjectRoute(for: keyword),
                    depth: depth + 1
                ))
            if recordThought, let output {
                let thoughtRoute = route.computeObjectRoute(for: keyword)
                thoughts.append(
                    Compute.Thought(
                        route: thoughtRoute,
                        depth: thoughtRoute.components.count,
                        keyword: keyword,
                        kind: kind(for: keyword),
                        input: .object([keyword: argument]),
                        output: output
                    ))
            }
            return output
        }

        func capture(
            _ operation: @Sendable () async throws -> JSON
        ) async -> (result: Result<JSON, JSONError>, thoughts: [Compute.Thought]) {
            let start = thoughts.count
            do {
                let value = try await operation()
                return (.success(value), Array(thoughts.dropFirst(start)))
            } catch {
                return (.failure(JSONError(error)), Array(thoughts.dropFirst(start)))
            }
        }

        func value(keyword: String, argument: JSON, frame: Compute.Frame) async throws -> JSON? {
            guard let function = functions[keyword] else { return nil }
            if function is any Compute.ReturnsKeywordDefinition {
                let dependency = Compute.Dependency(keyword: keyword, argument: argument)
                let route = dependencyOwner(frame.route.computeObjectRoute(for: keyword))
                tracked[route, default: []].insert(dependency)
                if let result = results[dependency] {
                    return try result.get()
                }
            }
            return try await function.compute(data: argument, frame: frame)
        }

        func registeredFunctions() -> [String: any AnyReturnsKeyword] {
            functions
        }

        func kind(for keyword: String) -> Compute.Thought.Kind {
            guard let function = functions[keyword] else { return .compute }
            return function is any Compute.ReturnsKeywordDefinition ? .returns : .compute
        }

        func dependenciesByRoute() -> [Compute.Route: Set<Compute.Dependency>] {
            tracked
        }

        func record(_ thought: Compute.Thought) {
            thoughts.append(thought)
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

    fileprivate func isPrefix(of route: Compute.Route) -> Bool {
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
            return lhs.path.lexicographicallyPrecedes(rhs.path)
        }
    }
}

extension Array where Element == Compute.Thought {
    fileprivate func sortedByRoute() -> [Compute.Thought] {
        sorted { lhs, rhs in
            if lhs.route.components.count != rhs.route.components.count {
                return lhs.route.components.count > rhs.route.components.count
            }
            return lhs.route.path.lexicographicallyPrecedes(rhs.route.path)
        }
    }
}
