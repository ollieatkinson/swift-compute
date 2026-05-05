public struct Count: Codable, Equatable, Sendable {
    public let of: JSON?

    public init(of: JSON? = nil) {
        self.of = of
    }
}

extension Count: ComputeKeyword {
    public static let keyword = "count"

    public func compute() throws -> JSON {
        .int((of ?? .null).countValue)
    }
}

extension Count: CustomComputeKeyword {
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
                depth: depth + 1
            )
        } catch {
            value = .null
        }
        return try Count(of: value).compute()
    }
}
