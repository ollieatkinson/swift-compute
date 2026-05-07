extension Keyword {
    public struct ApproximatelyEqual: Codable, Equatable, Sendable {
        @Computed public var lhs: JSON
        @Computed public var rhs: JSON
        public let accuracy: Double
    }
}

extension Keyword.ApproximatelyEqual: ComputeKeyword {
    public static let name = "approximately_equal"

    public func compute(in frame: ComputeFrame) async throws -> JSON? {
        let lhs = try await $lhs.compute(in: frame)
        let rhs = try await $rhs.compute(in: frame)
        return .bool(try abs(lhs.decode(Double.self) - rhs.decode(Double.self)) < accuracy)
    }
}
