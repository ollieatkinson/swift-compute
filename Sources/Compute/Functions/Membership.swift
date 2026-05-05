public struct Membership: Codable, Equatable, Sendable {
    public let lhs: JSON
    public let rhs: [JSON]

    public init(lhs: JSON, rhs: [JSON]) {
        self.lhs = lhs
        self.rhs = rhs
    }
}

extension Membership: ComputeKeyword {
    public static let keyword = "membership"

    public func compute() throws -> JSON {
        .bool(rhs.contains(lhs))
    }
}
