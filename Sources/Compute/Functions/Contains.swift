extension Keyword {
    public struct Contains: Codable, Equatable, Sendable, OperandPair {
        public let lhs: JSON
        public let rhs: JSON

        public init(lhs: JSON, rhs: JSON) {
            self.lhs = lhs
            self.rhs = rhs
        }
    }
}

extension Keyword.Contains: ComputeKeyword {
    public static let name = "contains"

    public func compute() throws -> JSON {
        .bool(try lhs.decode(String.self).contains(rhs.decode(String.self)))
    }
}
