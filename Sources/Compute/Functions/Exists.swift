public struct Exists: Codable, Equatable, Sendable {
    public let value: JSON?

    public init(value: JSON? = nil) {
        self.value = value
    }
}

extension Exists: ComputeKeyword {
    public static let keyword = "exists"

    public func compute() throws -> JSON {
        .bool((value ?? .null) != .null)
    }
}

extension Exists: CustomComputeKeyword {
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
        return try Exists(value: computed).compute()
    }
}
