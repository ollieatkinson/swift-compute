extension Compute.Keywords {
    public struct Contains: Codable, Equatable, Sendable, OperandPair {
        @Computed public var lhs: JSON
        @Computed public var rhs: JSON
    }
}

extension Compute.Keywords.Contains: Compute.Keyword {
    public static let name = "contains"

    public func compute(in frame: Compute.Frame) async throws -> JSON? {
        let lhs = try await $lhs.compute(in: frame)
        let rhs = try await $rhs.compute(in: frame)
        return .bool(try lhs.decode(String.self).contains(rhs.decode(String.self)))
    }
}
