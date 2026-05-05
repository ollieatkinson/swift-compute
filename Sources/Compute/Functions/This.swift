public struct This: Codable, Equatable, Sendable {
    public let value: JSON
    public let condition: JSON?

    public init(value: JSON, condition: JSON? = nil) {
        self.value = value
        self.condition = condition
    }
}

extension This: ComputeKeyword {
    public static let keyword = "this"

    public func compute() throws -> JSON {
        try selectedValue() ?? .null
    }
}

extension This {
    func selectedValue() throws -> JSON? {
        let condition = try condition?.decode(Bool.self) ?? true
        guard condition else { return nil }
        return value
    }
}

extension This: CustomComputeKeyword {
    func compute(
        context: Compute.Context,
        runtime: ComputeFunctionRuntime,
        route: ComputeRoute,
        depth: Int
    ) async throws -> JSON? {
        let condition = try await self.condition?
            .compute(
                context: context,
                runtime: runtime,
                route: route.appending(.key("condition")),
                depth: depth + 1
            )
            .decode(Bool.self) ?? true
        guard condition else { return nil }
        return try await self.value.compute(
            context: context,
            runtime: runtime,
            route: route.appending(.key("value")),
            depth: depth + 1
        )
    }
}
