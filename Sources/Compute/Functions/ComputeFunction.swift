public protocol AnyReturnsKeyword: Sendable {
    var keyword: String { get }
    func value(for input: JSON) async throws -> JSON
}

public protocol ComputeKeyword: Codable, Equatable, Sendable {
    static var keyword: String { get }
    func compute() throws -> JSON
}

protocol DirectComputeKeyword {
    static func computeDirectly(from input: JSON) throws -> JSON
}

public struct ComputeKeywordFunction<Keyword: ComputeKeyword>: AnyReturnsKeyword {
    private let computableRoutes: @Sendable (
        _ json: JSON,
        _ functions: [String: any AnyReturnsKeyword],
        _ route: ComputeRoute,
        _ argumentRoute: ComputeRoute
    ) -> [ComputeRoute]

    private let remainingThoughtCount: @Sendable (
        _ json: JSON,
        _ functions: [String: any AnyReturnsKeyword]
    ) -> Int

    private let compute: @Sendable (
        _ json: JSON,
        _ context: Compute.Context,
        _ runtime: ComputeFunctionRuntime,
        _ route: ComputeRoute,
        _ depth: Int
    ) async throws -> JSON?

    public var keyword: String {
        Keyword.keyword
    }

    public init() {
        if Keyword.self is any CustomComputeKeyword.Type {
            self.computableRoutes = { _, _, route, _ in
                [route]
            }
            self.remainingThoughtCount = { _, _ in
                1
            }
            self.compute = { argument, context, runtime, route, depth in
                guard let keyword = try JSON.decoded(Keyword.self, from: argument) as? any CustomComputeKeyword else {
                    return nil
                }
                return try await keyword.compute(
                    context: context,
                    runtime: runtime,
                    route: route,
                    depth: depth
                )
            }
        } else {
            self.computableRoutes = { argument, functions, route, argumentRoute in
                let childRoutes = argument.computableRoutes(functions: functions, from: argumentRoute)
                return childRoutes.isEmpty ? [route] : childRoutes
            }
            self.remainingThoughtCount = { argument, functions in
                argument.remainingThoughtCount(functions: functions) + 1
            }
            self.compute = { argument, context, runtime, route, depth in
                let computed = try await argument.compute(
                    context: context,
                    runtime: runtime,
                    route: route,
                    depth: depth + 1
                )
                return try await runtime.value(keyword: Keyword.keyword, argument: computed, route: route)
            }
        }
    }

    public func value(for input: JSON) async throws -> JSON {
        if let keyword = Keyword.self as? any DirectComputeKeyword.Type {
            return try keyword.computeDirectly(from: input)
        }
        return try JSON.decoded(Keyword.self, from: input).compute()
    }
}

public extension ComputeKeyword {
    static var function: ComputeKeywordFunction<Self> {
        ComputeKeywordFunction()
    }
}

public protocol ReturnsKeyword: AnyReturnsKeyword {
    func values(for input: JSON) -> AsyncStream<Result<JSON, JSONError>>
}

extension ReturnsKeyword {
    public func values(for input: JSON) -> AsyncStream<Result<JSON, JSONError>> {
        AsyncStream(bufferingPolicy: .unbounded) { continuation in
            let task = Task {
                do {
                    try await continuation.yield(.success(value(for: input)))
                } catch {
                    continuation.yield(.failure(JSONError(error)))
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}

protocol CustomComputeFunction: Sendable {
    var evaluatesChildrenInternally: Bool { get }

    func computableRoutes(
        argument: JSON,
        functions: [String: any AnyReturnsKeyword],
        route: ComputeRoute,
        argumentRoute: ComputeRoute
    ) -> [ComputeRoute]

    func remainingThoughtCount(
        argument: JSON,
        functions: [String: any AnyReturnsKeyword]
    ) -> Int

    func compute(
        argument: JSON,
        context: Compute.Context,
        runtime: ComputeFunctionRuntime,
        route: ComputeRoute,
        depth: Int
    ) async throws -> JSON?
}

protocol CustomComputeKeyword: ComputeKeyword {
    func compute(
        context: Compute.Context,
        runtime: ComputeFunctionRuntime,
        route: ComputeRoute,
        depth: Int
    ) async throws -> JSON?
}

extension CustomComputeKeyword {
    func compute(
        context: Compute.Context,
        runtime: ComputeFunctionRuntime,
        route: ComputeRoute,
        depth: Int
    ) async throws -> JSON? {
        let argument = try JSON.encoded(self)
        let computed = try await argument.compute(
            context: context,
            runtime: runtime,
            route: route,
            depth: depth + 1
        )
        return try await runtime.value(keyword: Self.keyword, argument: computed, route: route)
    }
}

extension ComputeKeywordFunction: CustomComputeFunction {
    var evaluatesChildrenInternally: Bool {
        Keyword.self is any CustomComputeKeyword.Type
    }

    func computableRoutes(
        argument: JSON,
        functions: [String: any AnyReturnsKeyword],
        route: ComputeRoute,
        argumentRoute: ComputeRoute
    ) -> [ComputeRoute] {
        computableRoutes(argument, functions, route, argumentRoute)
    }

    func remainingThoughtCount(
        argument: JSON,
        functions: [String: any AnyReturnsKeyword]
    ) -> Int {
        remainingThoughtCount(argument, functions)
    }

    func compute(
        argument: JSON,
        context: Compute.Context,
        runtime: ComputeFunctionRuntime,
        route: ComputeRoute,
        depth: Int
    ) async throws -> JSON? {
        try await compute(argument, context, runtime, route, depth)
    }
}
