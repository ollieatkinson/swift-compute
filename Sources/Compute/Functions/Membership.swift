extension Keyword {
    public struct Membership: Codable, Equatable, Sendable {
        public let lhs: JSON
        public let rhs: JSON

        public init(lhs: JSON, rhs: JSON) {
            self.lhs = lhs
            self.rhs = rhs
        }

        public init(lhs: JSON, rhs: [JSON]) {
            self.init(lhs: lhs, rhs: .array(rhs))
        }
    }
}

extension Keyword.Membership: ComputeKeyword {
    public static let name = "membership"

    public func compute(in frame: ComputeFrame) async throws -> JSON? {
        let lhs = try await lhs.compute(frame: frame["lhs"])
        let rhs = try await rhs.compute(frame: frame["rhs"])
        guard case .array(let values) = rhs else {
            throw JSONError("membership expected an array")
        }
        return .bool(values.contains(lhs))
    }
}
