extension Compute.Keyword {
    public struct Contains: Codable, Equatable, Sendable {
        @Computed public var lhs: String
        @Computed public var rhs: String
    }
}

extension Compute.Keyword.Contains: Compute.KeywordDefinition {
    public static let name = "contains"

    public func compute(in frame: Compute.Frame) async throws -> JSON? {
        let lhs = try await $lhs.compute(in: frame)
        let rhs = try await $rhs.compute(in: frame)
        return .bool(lhs.contains(rhs))
    }
}
