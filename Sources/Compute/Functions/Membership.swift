extension Compute.Keywords {
    public struct Membership: Codable, Equatable, Sendable {
        @Computed public var lhs: JSON
        @Computed public var rhs: JSON
    }
}

extension Compute.Keywords.Membership: Compute.Keyword {
    public static let name = "membership"

    public func compute(in frame: Compute.Frame) async throws -> JSON? {
        let lhs = try await $lhs.compute(in: frame)
        let rhs = try await $rhs.compute(in: frame)
        guard case .array(let values) = rhs else {
            throw JSONError("membership expected an array")
        }
        return .bool(values.contains(lhs))
    }
}
