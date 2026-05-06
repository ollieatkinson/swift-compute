extension Keyword {
    public struct Exists: Codable, Equatable, Sendable {
        public let value: JSON?

        public init(value: JSON? = nil) {
            self.value = value
        }
    }
}

extension Keyword.Exists: ComputeKeyword {
    public static let name = "exists"

    public func compute() throws -> JSON {
        .bool((value ?? .null) != .null)
    }
}

extension Keyword.Exists: CustomComputeKeyword {
    func compute(
        context: Compute.Context,
        runtime: ComputeFunctionRuntime,
        route: ComputeRoute,
        depth: Int
    ) async throws -> JSON? {
        let computed: JSON
        do {
            computed = try await (value ?? .null).compute(
                context: context,
                runtime: runtime,
                route: route.appending(.key("value")),
                depth: depth + 1
            )
        } catch {
            computed = .null
        }
        return try Self(value: computed).compute()
    }
}
