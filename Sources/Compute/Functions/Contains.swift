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

    public func compute(in frame: ComputeFrame) async throws -> JSON? {
        let lhs = try await lhs.compute(frame: frame["lhs"])
        let rhs = try await rhs.compute(frame: frame["rhs"])
        return .bool(try lhs.decode(String.self).contains(rhs.decode(String.self)))
    }
}
