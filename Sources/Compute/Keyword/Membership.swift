extension Compute.Keyword {
    public struct Membership: Codable, Equatable, Sendable {
        @Computed public var lhs: JSON
        @Computed public var rhs: [JSON]
    }
}

extension Compute.Keyword.Membership: Compute.KeywordDefinition {
    public static let name = "membership"

    public func compute(in frame: Compute.Frame) async throws -> JSON? {
        let lhs = try await $lhs.compute(in: frame)
        let rhs = try await $rhs.compute(in: frame)
        return .bool(rhs.contains(lhs))
    }
}
