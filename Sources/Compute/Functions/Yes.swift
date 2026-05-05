public struct Yes: Codable, Equatable, Sendable {
    public let `if`: JSON?
    public let unless: JSON?

    public init(if conditions: JSON? = nil, unless exceptions: JSON? = nil) {
        self.if = conditions
        self.unless = exceptions
    }
}

extension Yes: ComputeKeyword {
    public static let keyword = "yes"
    public static let function = YesFunction()

    public func compute() throws -> JSON {
        let conditions = `if`?.conditionList ?? []
        let exceptions = unless?.conditionList ?? []
        let satisfied = try conditions.allSatisfy { try $0.decode(Bool.self) }
        let blocked = try exceptions.contains { try $0.decode(Bool.self) }
        return .bool(satisfied && !blocked)
    }
}

public struct YesFunction: AnyReturnsKeyword {
    public let keyword = Yes.keyword

    public init() {}

    public func value(for input: JSON) async throws -> JSON {
        try Yes.computeDirectly(from: input)
    }
}

extension YesFunction: CustomComputeFunction {
    var evaluatesChildrenInternally: Bool {
        false
    }

    func computableRoutes(
        argument: JSON,
        functions: [String: any AnyReturnsKeyword],
        route: ComputeRoute,
        argumentRoute: ComputeRoute
    ) -> [ComputeRoute] {
        let childRoutes = argument.computableRoutes(functions: functions, from: argumentRoute)
        return childRoutes.isEmpty ? [route] : childRoutes
    }

    func remainingThoughtCount(
        argument: JSON,
        functions: [String: any AnyReturnsKeyword]
    ) -> Int {
        argument.remainingThoughtCount(functions: functions) + 1
    }

    func compute(
        argument: JSON,
        context: Compute.Context,
        runtime: ComputeFunctionRuntime,
        route: ComputeRoute,
        depth: Int
    ) async throws -> JSON? {
        let computed = try await argument.computeIfNeeded(
            context: context,
            runtime: runtime,
            route: route,
            depth: depth + 1
        )
        return try await value(for: computed)
    }
}

extension Yes: DirectComputeKeyword {
    static func computeDirectly(from input: JSON) throws -> JSON {
        guard case .object(let object) = input else {
            return try JSON.decoded(Yes.self, from: input).compute()
        }
        let conditions = object["if"]?.conditionList ?? []
        for condition in conditions where try !condition.boolValue() {
            return .bool(false)
        }
        let exceptions = object["unless"]?.conditionList ?? []
        for exception in exceptions where try exception.boolValue() {
            return .bool(false)
        }
        return .bool(true)
    }
}

private extension JSON {
    func boolValue() throws -> Bool {
        if case .bool(let value) = self {
            return value
        }
        return try decode(Bool.self)
    }
}
