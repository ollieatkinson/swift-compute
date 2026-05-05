import Foundation

public enum ComputeThoughtKind: String, Codable, Equatable, Sendable {
    case compute
    case returns
    case defaultValue
    case error
}

public struct ComputeThought: Codable, Equatable, Sendable {
    public let route: ComputeRoute
    public let depth: Int
    public let keyword: String
    public let kind: ComputeThoughtKind
    public let input: JSON?
    public let output: JSON?
    public let error: JSONError?
    public let state: JSON?

    public init(
        route: ComputeRoute,
        depth: Int,
        keyword: String,
        kind: ComputeThoughtKind = .compute,
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

public struct ComputeStep: Sendable, Equatable {
    public let state: JSON
    public let thoughts: [ComputeThought]
    public let remainingThoughts: Int

    public var isThinking: Bool {
        remainingThoughts > 0
    }

    public init(state: JSON, thoughts: [ComputeThought], remainingThoughts: Int) {
        self.state = state
        self.thoughts = thoughts
        self.remainingThoughts = remainingThoughts
    }
}

private enum ComputeLemma: Hashable, Sendable {
    case source(ComputeRoute)
    case route(ComputeRoute)
    case dependency(String)
}

private enum ComputeSignal: Equatable, Sendable {
    case value(JSON)
    case failure(JSONError)

    var value: JSON? {
        guard case .value(let value) = self else { return nil }
        return value
    }
}

private struct RouteContinuation {
    var continuation: AsyncStream<Result<JSON, JSONError>>.Continuation
    var last: Result<JSON, JSONError>?
}

public actor ComputeRuntime: Sendable {
    private typealias ComputeBrain = Brain<ComputeLemma, ComputeSignal>

    private struct Graph: Sendable {
        let concepts: [ComputeBrain.Concept]
        let state: ComputeBrain.State
        let change: ComputeBrain.State
        let routeConcepts: Set<ComputeRoute>
    }

    private let document: JSON
    private let context: Compute.Context?
    private let functions: [String: any AnyReturnsKeyword]
    private let brain: ComputeBrain
    private var routeConcepts: Set<ComputeRoute>
    private var routeDependencies: [ComputeRoute: Set<ComputeDependency>] = [:]
    private var latestThoughts: [ComputeThought] = []
    private var functionResults: [String: Result<JSON, JSONError>] = [:]
    private var subscriptions: [String: Task<Void, Never>] = [:]
    private var observedRoutes: Set<ComputeRoute> = []
    private var routeContinuations: [ComputeRoute: [UUID: RouteContinuation]] = [:]

    public init(
        document: JSON,
        context: Compute.Context? = nil,
        functions: [any AnyReturnsKeyword] = [],
        computer: Computer = .default
    ) {
        let computer = computer.merging(functions)
        let graph = ComputeProfiling.measure("runtime.init.graph") {
            Self.graph(
                document: document,
                functions: computer.functions,
                routeDependencies: [:]
            )
        }
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
        let profile = ComputeProfiling.start()
        do {
            let value = (try await settle(subscribe: false)).state
            ComputeProfiling.record("runtime.value", since: profile)
            return value
        } catch {
            ComputeProfiling.record("runtime.value", since: profile)
            throw error
        }
    }

    public func decode<Value: Decodable>(_ type: Value.Type = Value.self) async throws -> Value {
        try await value().decode(Value.self)
    }

    public func value(at route: ComputeRoute) async throws -> JSON? {
        (try await value()).routeValue(at: route)
    }

    public func decode<Value: Decodable>(
        _ type: Value.Type = Value.self,
        at route: ComputeRoute
    ) async throws -> Value? {
        try await value(at: route)?.decode(Value.self)
    }

    @discardableResult
    public func step(_ count: Int = 1) async throws -> ComputeStep {
        let runtime = functionRuntime()
        let profile = ComputeProfiling.start()
        let commit: BrainCommit<ComputeLemma, ComputeSignal>
        do {
            commit = try await brain.commit(thoughts: count, thinking: thinking(with: runtime))
            ComputeProfiling.record("runtime.brain.commit", since: profile)
        } catch {
            ComputeProfiling.record("runtime.brain.commit", since: profile)
            throw error
        }
        return try await finish(
            commit,
            runtime: runtime,
            subscribe: false,
            publishWhenSettled: true,
            sortThoughts: true
        )
    }

    public nonisolated func run(at route: ComputeRoute = .root) -> AsyncStream<Result<JSON, JSONError>> {
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
        route: ComputeRoute
    ) async {
        routeContinuations[route, default: [:]][id] = RouteContinuation(continuation: continuation)
        observedRoutes.insert(route)
        do {
            try await settle(subscribe: true, reset: true)
        } catch {
            yield(.failure(JSONError(error)), to: route)
        }
    }

    private func removeRouteContinuation(id: UUID, route: ComputeRoute) {
        routeContinuations[route]?[id] = nil
        if routeContinuations[route]?.isEmpty ?? false {
            routeContinuations[route] = nil
            observedRoutes.remove(route)
        }
        cancelSubscriptionsIfIdle()
    }

    @discardableResult
    private func settle(subscribe: Bool, reset: Bool = false) async throws -> ComputeStep {
        let graph: Graph?
        if reset {
            let profile = ComputeProfiling.start()
            let resetGraph = Self.graph(
                document: document,
                functions: functions,
                routeDependencies: routeDependencies
            )
            ComputeProfiling.record("runtime.settle.resetGraph", since: profile)
            routeConcepts = resetGraph.routeConcepts
            graph = resetGraph
        } else {
            graph = nil
        }
        let runtime = functionRuntime()
        let commit: BrainCommit<ComputeLemma, ComputeSignal>
        do {
            let brainProfile = ComputeProfiling.start()
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
            ComputeProfiling.record("runtime.brain.settle", since: brainProfile)
        } catch BrainError.thoughtLimitExceeded {
            throw ComputeError.recursionLimitExceeded
        } catch {
            let jsonError = JSONError(error)
            if !latestThoughts.contains(where: { $0.keyword == "error" }) {
                latestThoughts.append(ComputeThought(route: .root, depth: 0, keyword: "error", kind: .error, error: jsonError))
            }
            throw jsonError
        }
        let finishProfile = ComputeProfiling.start()
        do {
            let step = try await finish(commit, runtime: runtime, subscribe: subscribe, publishWhenSettled: true)
            ComputeProfiling.record("runtime.finish", since: finishProfile)
            return step
        } catch {
            ComputeProfiling.record("runtime.finish", since: finishProfile)
            throw error
        }
    }

    public var thoughts: [ComputeThought] {
        latestThoughts.sortedByRoute()
    }

    private func finish(
        _ commit: BrainCommit<ComputeLemma, ComputeSignal>,
        runtime: ComputeFunctionRuntime,
        subscribe: Bool,
        publishWhenSettled: Bool,
        sortThoughts: Bool = false
    ) async throws -> ComputeStep {
        let takeThoughtsProfile = ComputeProfiling.start()
        latestThoughts = await runtime.takeThoughts()
        ComputeProfiling.record("runtime.finish.takeThoughts", since: takeThoughtsProfile)
        if let error = latestThoughts.compactMap(\.error).first {
            throw error
        }
        let stepThoughts = sortThoughts ? latestThoughts.sortedByRoute() : latestThoughts

        let documentProfile = ComputeProfiling.start()
        let state = try document(from: commit.state)
        ComputeProfiling.record("runtime.finish.document", since: documentProfile)
        let step = ComputeStep(state: state, thoughts: stepThoughts, remainingThoughts: commit.remainingThoughts)
        let dependenciesProfile = ComputeProfiling.start()
        let tracked = await runtime.dependenciesByRoute()
        ComputeProfiling.record("runtime.finish.dependencies", since: dependenciesProfile)
        let mergeProfile = ComputeProfiling.start()
        let didMerge = merge(tracked)
        ComputeProfiling.record("runtime.finish.mergeDependencies", since: mergeProfile)
        if didMerge {
            let updateGraphProfile = ComputeProfiling.start()
            let graph = Self.graph(
                document: document,
                functions: functions,
                routeDependencies: routeDependencies
            )
            ComputeProfiling.record("runtime.finish.updateGraph", since: updateGraphProfile)
            routeConcepts = graph.routeConcepts
            await brain.update(concepts: graph.concepts)
        }
        if subscribe || !observedRoutes.isEmpty {
            let resubscribeProfile = ComputeProfiling.start()
            resubscribe(to: Array(routeDependencies.values.flatMap { $0 }))
            ComputeProfiling.record("runtime.finish.resubscribe", since: resubscribeProfile)
        }
        if publishWhenSettled, !step.isThinking {
            let publishProfile = ComputeProfiling.start()
            publish(step.state)
            ComputeProfiling.record("runtime.finish.publish", since: publishProfile)
        }
        return step
    }

    private func merge(_ tracked: [ComputeRoute: Set<ComputeDependency>]) -> Bool {
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

    private func resubscribe(to dependencies: [ComputeDependency]) {
        let next = Dictionary(dependencies.map { ($0.key, $0) }, uniquingKeysWith: { first, _ in first })
        for (key, task) in subscriptions where next[key] == nil {
            task.cancel()
            subscriptions[key] = nil
        }
        for (key, dependency) in next where subscriptions[key] == nil {
            guard let function = functions[dependency.keyword] as? any ReturnsKeyword else { continue }
            subscriptions[key] = Task { [weak self] in
                for await result in function.values(for: dependency.argument) {
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

    private func apply(_ result: Result<JSON, JSONError>, to dependency: ComputeDependency) async {
        functionResults[dependency.key] = result
        let signal: ComputeSignal
        switch result {
        case .success(let value):
            signal = .value(value)
        case .failure(let error):
            signal = .failure(error)
        }
        await brain.stage([.dependency(dependency.key): signal])
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
            if let value = state.routeValue(at: route) {
                result = .success(value)
            } else {
                result = .failure(JSONError("Missing value", path: route.path))
            }
            yield(result, to: route)
        }
    }

    private func yield(_ result: Result<JSON, JSONError>, to route: ComputeRoute) {
        guard var continuations = routeContinuations[route] else { return }
        for id in continuations.keys {
            guard continuations[id]?.last != result else { continue }
            continuations[id]?.last = result
            continuations[id]?.continuation.yield(result)
        }
        routeContinuations[route] = continuations
    }

    private func functionRuntime() -> ComputeFunctionRuntime {
        let routes = routeConcepts
        return ComputeFunctionRuntime(functions: functions, results: functionResults) { route in
            route.nearestAncestor(in: routes) ?? route
        }
    }

    private func thinking(with runtime: ComputeFunctionRuntime) -> ComputeBrain.Thinking {
        let context = context ?? ComputeTaskLocal.context
        return { lemma, state in
            guard case .route(let route) = lemma else { return nil }
            return try await ComputeTaskLocal.$context.withValue(context) {
                try await self.evaluate(route, state: state, runtime: runtime)
            }
        }
    }

    private func evaluate(
        _ route: ComputeRoute,
        state: ComputeBrain.State,
        runtime: ComputeFunctionRuntime
    ) async throws -> ComputeSignal? {
        let profile = ComputeProfiling.start()
        do {
            guard case .object(let object)? = try value(at: route, from: state) else {
                ComputeProfiling.record("runtime.evaluateRoute", since: profile)
                return nil
            }
            let step = try await Self.evaluate(object, at: route, runtime: runtime)
            await runtime.record(ComputeThought(
                route: route,
                depth: route.components.count,
                keyword: step.keyword,
                kind: step.kind,
                input: step.input,
                output: step.output
            ))
            ComputeProfiling.record("runtime.evaluateRoute", since: profile)
            return .value(step.output)
        } catch {
            ComputeProfiling.record("runtime.evaluateRoute", since: profile)
            throw error
        }
    }

    private func value(
        at route: ComputeRoute,
        from state: ComputeBrain.State
    ) throws -> JSON? {
        let profile = ComputeProfiling.start()
        do {
            guard var output = document.routeValue(at: route) else {
                ComputeProfiling.record("runtime.valueAtState", since: profile)
                return nil
            }
            var finalAncestors: [ComputeRoute] = []
            let baseDepth = route.components.count
            let routeValues = state.compactMap { entry -> (ComputeRoute, JSON)? in
                guard case .route(let candidate) = entry.key else { return nil }
                guard route.isPrefix(of: candidate), candidate != route else { return nil }
                guard case .value(let value) = entry.value else { return nil }
                return (ComputeRoute(Array(candidate.components.dropFirst(baseDepth))), value)
            }.sorted { lhs, rhs in
                if lhs.0.components.count != rhs.0.components.count {
                    return lhs.0.components.count < rhs.0.components.count
                }
                return lhs.0.pathLexicographicallyPrecedes(rhs.0)
            }
            for (relativeRoute, value) in routeValues {
                guard !finalAncestors.contains(where: { $0.isPrefix(of: relativeRoute) }) else { continue }
                try output.set(value, at: relativeRoute)
                if !value.isComputeInvocation {
                    finalAncestors.append(relativeRoute)
                }
            }
            ComputeProfiling.record("runtime.valueAtState", since: profile)
            return output
        } catch {
            ComputeProfiling.record("runtime.valueAtState", since: profile)
            throw error
        }
    }

    private static func evaluate(
        _ object: [String: JSON],
        at route: ComputeRoute,
        runtime: ComputeFunctionRuntime
    ) async throws -> (keyword: String, kind: ComputeThoughtKind, input: JSON, output: JSON) {
        let profile = ComputeProfiling.start()
        do {
            let context = ComputeTaskLocal.context
            if let invocation = Compute.Invocation(object: object) {
                let functionRoute = route.appending(.key("{returns}")).appending(.key(invocation.keyword))
                do {
                    if let output = try await runtime.compute(
                        keyword: invocation.keyword,
                        argument: invocation.argument,
                        context: context,
                        route: functionRoute,
                        depth: route.components.count + 1,
                        recordThought: false
                    ) {
                        let result = (invocation.keyword, await runtime.kind(for: invocation.keyword), invocation.returnsJSON, output)
                        ComputeProfiling.record("runtime.evaluateInvocation", since: profile)
                        return result
                    }
                    guard let fallback = invocation.fallback else {
                        let result = (invocation.keyword, await runtime.kind(for: invocation.keyword), invocation.returnsJSON, JSON.null)
                        ComputeProfiling.record("runtime.evaluateInvocation", since: profile)
                        return result
                    }
                    let output = try await fallback.compute(
                        context: context,
                        runtime: runtime,
                        route: route.appending(.key("default")),
                        depth: route.components.count + 1
                    )
                    ComputeProfiling.record("runtime.evaluateInvocation", since: profile)
                    return ("default", .defaultValue, fallback, output)
                } catch {
                    guard let fallback = invocation.fallback else {
                        throw error
                    }
                    let output = try await fallback.compute(
                        context: context,
                        runtime: runtime,
                        route: route.appending(.key("default")),
                        depth: route.components.count + 1
                    )
                    ComputeProfiling.record("runtime.evaluateInvocation", since: profile)
                    return ("default", .defaultValue, fallback, output)
                }
            }
            throw JSONError("Unsupported compute object", path: route.path)
        } catch {
            ComputeProfiling.record("runtime.evaluateInvocation", since: profile)
            throw error
        }
    }

    private static func graph(
        document: JSON,
        functions: [String: any AnyReturnsKeyword],
        routeDependencies: [ComputeRoute: Set<ComputeDependency>]
    ) -> Graph {
        let conceptRoutes = ComputeProfiling.measure("graph.conceptRoutes") {
            document.conceptRoutes(functions: functions)
        }
        let routes = ComputeProfiling.measure("graph.sortRoutes") {
            conceptRoutes.sortedForComputeEvaluation()
        }
        let routeConcepts = Set(routes)
        let directChildProfile = ComputeProfiling.start()
        let routeChildren = directChildConcepts(for: routes, in: routeConcepts)
        ComputeProfiling.record("graph.directChildConcepts", since: directChildProfile)
        var state: ComputeBrain.State = [:]
        var change: ComputeBrain.State = [:]
        var concepts: [ComputeBrain.Concept] = []

        ComputeProfiling.measure("graph.buildConcepts") {
            for route in routes {
                guard let value = document.routeValue(at: route) else { continue }
                state[.route(route)] = .value(value)
                state[.source(route)] = .value(value)
                change[.source(route)] = .value(value)
                concepts.append(ComputeBrain.Concept(
                    .route(route),
                    inputs: inputs(
                        for: route,
                        value: value,
                        functions: functions,
                        childConcepts: routeChildren[route] ?? [],
                        routeDependencies: routeDependencies
                    )
                ))
            }
        }
        return Graph(concepts: concepts, state: state, change: change, routeConcepts: routeConcepts)
    }

    private static func inputs(
        for route: ComputeRoute,
        value: JSON,
        functions: [String: any AnyReturnsKeyword],
        childConcepts: [ComputeRoute],
        routeDependencies: [ComputeRoute: Set<ComputeDependency>]
    ) -> Set<ComputeLemma> {
        var inputs: Set<ComputeLemma> = []
        if case .object(let object) = value, let invocation = Compute.Invocation(object: object) {
            let function = functions[invocation.keyword]
            if let custom = function as? any CustomComputeFunction, custom.evaluatesChildrenInternally {
                inputs.insert(.source(route))
            } else {
                if childConcepts.isEmpty {
                    inputs.insert(.source(route))
                } else {
                    inputs.formUnion(childConcepts.map { .route($0) })
                }
            }
        } else {
            inputs.insert(.source(route))
        }
        inputs.formUnion((routeDependencies[route] ?? []).map { .dependency($0.key) })
        return inputs
    }

    private static func directChildConcepts(
        for routes: [ComputeRoute],
        in routeConcepts: Set<ComputeRoute>
    ) -> [ComputeRoute: [ComputeRoute]] {
        var children: [ComputeRoute: [ComputeRoute]] = [:]
        for route in routes {
            guard let ancestor = route.nearestStrictAncestor(in: routeConcepts) else { continue }
            children[ancestor, default: []].append(route)
        }
        return children
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
        excluding excluded: ComputeRoute? = nil
    ) throws -> JSON {
        if excluded == nil,
           case .value(let rootValue)? = state[.route(.root)],
           !rootValue.isComputeInvocation {
            return rootValue
        }
        var output = document
        var finalAncestors: [ComputeRoute] = []
        let routeValues = state.compactMap { entry -> (ComputeRoute, JSON)? in
            guard case .route(let route) = entry.key else { return nil }
            guard !route.isExcluded(from: excluded) else { return nil }
            guard case .value(let value) = entry.value else { return nil }
            return (route, value)
        }.sorted { lhs, rhs in
            if lhs.0.components.count != rhs.0.components.count {
                return lhs.0.components.count < rhs.0.components.count
            }
            return lhs.0.pathLexicographicallyPrecedes(rhs.0)
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

public struct ComputeDependency: Sendable, Equatable, Hashable {
    public let keyword: String
    public let argument: JSON

    fileprivate var key: String {
        "\(keyword):\(argument.stableDescription)"
    }

    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.key == rhs.key
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(key)
    }
}

actor ComputeFunctionRuntime {
    private let functions: [String: any AnyReturnsKeyword]
    private let results: [String: Result<JSON, JSONError>]
    private let dependencyOwner: @Sendable (ComputeRoute) -> ComputeRoute
    private var tracked: [ComputeRoute: Set<ComputeDependency>] = [:]
    private var thoughts: [ComputeThought] = []

    init(
        functions: [String: any AnyReturnsKeyword],
        results: [String: Result<JSON, JSONError>],
        dependencyOwner: @escaping @Sendable (ComputeRoute) -> ComputeRoute
    ) {
        self.functions = functions
        self.results = results
        self.dependencyOwner = dependencyOwner
    }

    func compute(
        keyword: String,
        argument: JSON,
        context: Compute.Context,
        route: ComputeRoute,
        depth: Int,
        recordThought: Bool = true
    ) async throws -> JSON? {
        guard let function = functions[keyword] else { return nil }
        let rawOutput: JSON?
        if let custom = function as? any CustomComputeFunction {
            rawOutput = try await custom.compute(
                argument: argument,
                context: context,
                runtime: self,
                route: route,
                depth: depth
            )
        } else {
            let computed = try await argument.compute(
                context: context,
                runtime: self,
                route: route,
                depth: depth + 1
            )
            rawOutput = try await value(keyword: keyword, argument: computed, route: route)
        }
        let output = try await rawOutput?.compute(
            context: context,
            runtime: self,
            route: route.computeObjectRoute(for: keyword),
            depth: depth + 1
        )
        if recordThought, let output {
            let thoughtRoute = route.computeObjectRoute(for: keyword)
            thoughts.append(ComputeThought(
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

    func value(keyword: String, argument: JSON, route: ComputeRoute) async throws -> JSON? {
        guard let function = functions[keyword] else { return nil }
        if function is any ReturnsKeyword {
            let dependency = ComputeDependency(keyword: keyword, argument: argument)
            let route = dependencyOwner(route.computeObjectRoute(for: keyword))
            tracked[route, default: []].insert(dependency)
            if let result = results[dependency.key] {
                return try result.get()
            }
        }
        return try await function.value(for: argument)
    }

    func registeredFunctions() -> [String: any AnyReturnsKeyword] {
        functions
    }

    func kind(for keyword: String) -> ComputeThoughtKind {
        guard let function = functions[keyword] else { return .compute }
        return function is any ReturnsKeyword ? .returns : .compute
    }

    func dependenciesByRoute() -> [ComputeRoute: Set<ComputeDependency>] {
        tracked
    }

    func record(_ thought: ComputeThought) {
        thoughts.append(thought)
    }

    func takeThoughts() -> [ComputeThought] {
        defer { thoughts.removeAll(keepingCapacity: true) }
        return thoughts
    }
}

private extension ComputeRoute {
    func computeObjectRoute(for keyword: String) -> ComputeRoute {
        guard components.count >= 2 else { return self }
        guard components[components.count - 2] == .key("{returns}") else { return self }
        guard components[components.count - 1] == .key(keyword) else { return self }
        return ComputeRoute(Array(components.dropLast(2)))
    }

    func isPrefix(of route: ComputeRoute) -> Bool {
        guard components.count <= route.components.count else { return false }
        return zip(components, route.components).allSatisfy(==)
    }

    func isExcluded(from excluded: ComputeRoute?) -> Bool {
        guard let excluded else { return false }
        return self == excluded || isPrefix(of: excluded)
    }

    func nearestAncestor(in routes: Set<ComputeRoute>) -> ComputeRoute? {
        var components = components
        while true {
            let route = ComputeRoute(components)
            if routes.contains(route) {
                return route
            }
            guard !components.isEmpty else { return nil }
            components.removeLast()
        }
    }

    func nearestStrictAncestor(in routes: Set<ComputeRoute>) -> ComputeRoute? {
        var components = components
        while !components.isEmpty {
            components.removeLast()
            let route = ComputeRoute(components)
            if routes.contains(route) {
                return route
            }
        }
        return nil
    }

    func pathLexicographicallyPrecedes(_ route: ComputeRoute) -> Bool {
        for (lhs, rhs) in zip(components, route.components) {
            let lhsPath = lhs.pathComponent
            let rhsPath = rhs.pathComponent
            if lhsPath == rhsPath {
                continue
            }
            return lhsPath < rhsPath
        }
        return components.count < route.components.count
    }
}

private extension ComputeRoute.Component {
    var pathComponent: String {
        switch self {
        case .key(let key):
            return key
        case .index(let index):
            return String(index)
        }
    }
}

private extension Array where Element == ComputeRoute {
    func sortedForComputeEvaluation() -> [ComputeRoute] {
        sorted { lhs, rhs in
            if lhs.components.count != rhs.components.count {
                return lhs.components.count > rhs.components.count
            }
            return lhs.pathLexicographicallyPrecedes(rhs)
        }
    }
}

private extension Array where Element == ComputeThought {
    func sortedByRoute() -> [ComputeThought] {
        sorted { lhs, rhs in
            if lhs.route.components.count != rhs.route.components.count {
                return lhs.route.components.count > rhs.route.components.count
            }
            return lhs.route.pathLexicographicallyPrecedes(rhs.route)
        }
    }
}
