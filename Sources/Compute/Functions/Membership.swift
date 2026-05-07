extension Keyword {
    public struct Membership: Codable, Equatable, Sendable {
        @Computed public var lhs: JSON
        @Computed public var rhs: JSON
    }
}

extension Keyword.Membership: ComputeKeyword {
    public static let name = "membership"

    public func compute(in frame: ComputeFrame) async throws -> JSON? {
        let lhs = try await $lhs.compute(in: frame)
        let rhs = try await $rhs.compute(in: frame)
        guard case .array(let values) = rhs else {
            throw JSONError("membership expected an array")
        }
        return .bool(values.contains(lhs))
    }
}
