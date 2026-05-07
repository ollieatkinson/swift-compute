extension Keyword {
    public struct Count: Codable, Equatable, Sendable {
        public let of: JSON?

        public init(of: JSON? = nil) {
            self.of = of
        }
    }
}

extension Keyword.Count: ComputeKeyword {
    public static let name = "count"

    public func compute() throws -> JSON {
        .int((of ?? .null).countValue)
    }
}

extension Keyword.Count: CustomComputeKeyword {
    func compute(
        context: Compute.Context,
        runtime: ComputeFunctionRuntime,
        route: ComputeRoute,
        depth: Int
    ) async throws -> JSON? {
        let value: JSON
        do {
            value = try await (of ?? .null).compute(
                context: context,
                runtime: runtime,
                route: route.appending(.key("of")),
                depth: depth
            )
        } catch {
            value = .null
        }
        return try Self(of: value).compute()
    }
}
