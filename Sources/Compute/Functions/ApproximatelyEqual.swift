extension Keyword {
    public struct ApproximatelyEqual: Codable, Equatable, Sendable {
        public let lhs: JSON
        public let rhs: JSON
        public let accuracy: Double

        public init(lhs: JSON, rhs: JSON, accuracy: Double) {
            self.lhs = lhs
            self.rhs = rhs
            self.accuracy = accuracy
        }
    }
}

extension Keyword.ApproximatelyEqual: ComputeKeyword {
    public static let name = "approximately_equal"

    public func compute(in frame: ComputeFrame) async throws -> JSON? {
        let lhs = try await lhs.compute(frame: frame["lhs"])
        let rhs = try await rhs.compute(frame: frame["rhs"])
        return .bool(try abs(lhs.decode(Double.self) - rhs.decode(Double.self)) < accuracy)
    }
}
