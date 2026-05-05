public struct Either: Equatable, Sendable {
    public let branches: [This]

    public init(_ branches: [This]) {
        self.branches = branches
    }
}

extension Either: Codable {
    public init(from decoder: Decoder) throws {
        self.init(try [This](from: decoder))
    }

    public func encode(to encoder: Encoder) throws {
        try branches.encode(to: encoder)
    }
}

extension Either: ComputeKeyword {
    public static let keyword = "either"

    public func compute() throws -> JSON {
        for branch in branches {
            if let value = try branch.selectedValue() {
                return value
            }
        }
        return .null
    }
}

extension Either: CustomComputeKeyword {
    func compute(
        context: Compute.Context,
        runtime: ComputeFunctionRuntime,
        route: ComputeRoute,
        depth: Int
    ) async throws -> JSON? {
        for (index, branch) in branches.enumerated() {
            let branchRoute = route.appending(.index(index))
            let condition = try await branch.condition?
                .compute(
                    context: context,
                    runtime: runtime,
                    route: branchRoute.appending(.key("condition")),
                    depth: depth + 1
                )
                .decode(Bool.self) ?? true
            guard condition else { continue }
            return try await branch.value.compute(
                context: context,
                runtime: runtime,
                route: branchRoute.appending(.key("value")),
                depth: depth + 1
            )
        }
        return nil
    }
}
