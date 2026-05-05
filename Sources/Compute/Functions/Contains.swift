public struct Contains: Codable, Equatable, Sendable, OperandPair {
    public let lhs: JSON
    public let rhs: JSON

    public init(lhs: JSON, rhs: JSON) {
        self.lhs = lhs
        self.rhs = rhs
    }
}

extension Contains: ComputeKeyword {
    public static let keyword = "contains"

    public func compute() throws -> JSON {
        .bool(try lhs.decode(String.self).contains(rhs.decode(String.self)))
    }
}
