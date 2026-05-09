import _JSON
extension Compute.Keyword {
    public struct ApproximatelyEqual: Codable, Equatable, Sendable {
        @Computed public var lhs: Double
        @Computed public var rhs: Double
        public let accuracy: Double
    }
}

extension Compute.Keyword.ApproximatelyEqual: Compute.KeywordDefinition {
    public static let name = "approximately_equal"

    public func compute(in frame: Compute.Frame) async throws -> JSON? {
        let lhs = try await $lhs.compute(in: frame)
        let rhs = try await $rhs.compute(in: frame)
        return .bool(abs(lhs - rhs) < accuracy)
    }
}
