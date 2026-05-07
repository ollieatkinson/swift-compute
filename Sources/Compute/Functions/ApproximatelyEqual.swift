extension Compute.Keywords {
    public struct ApproximatelyEqual: Codable, Equatable, Sendable {
        @Computed public var lhs: JSON
        @Computed public var rhs: JSON
        public let accuracy: Double
    }
}

extension Compute.Keywords.ApproximatelyEqual: Compute.Keyword {
    public static let name = "approximately_equal"

    public func compute(in frame: Compute.Frame) async throws -> JSON? {
        let lhs = try await $lhs.compute(in: frame)
        let rhs = try await $rhs.compute(in: frame)
        return .bool(try abs(lhs.decode(Double.self) - rhs.decode(Double.self)) < accuracy)
    }
}
