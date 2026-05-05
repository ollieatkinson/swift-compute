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

extension ApproximatelyEqual: ComputeKeyword {
    public static let keyword = "approximately_equal"

    public func compute() throws -> JSON {
        .bool(try abs(lhs.decode(Double.self) - rhs.decode(Double.self)) < accuracy)
    }
}
