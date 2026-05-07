extension Keyword {
    public struct Contains: Codable, Equatable, Sendable, OperandPair {
        @Computed public var lhs: JSON
        @Computed public var rhs: JSON
    }
}

extension Keyword.Contains: ComputeKeyword {
    public static let name = "contains"

    public func compute(in frame: ComputeFrame) async throws -> JSON? {
        let lhs = try await $lhs.compute(in: frame)
        let rhs = try await $rhs.compute(in: frame)
        return .bool(try lhs.decode(String.self).contains(rhs.decode(String.self)))
    }
}
