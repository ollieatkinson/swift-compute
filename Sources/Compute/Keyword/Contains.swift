import _JSON
extension Compute.Keyword {
    public struct Contains: Codable, Equatable, Sendable {
        @Computed public var lhs: JSON
        @Computed public var rhs: JSON
    }
}

extension Compute.Keyword.Contains: Compute.KeywordDefinition {
    public static let name = "contains"

    public func compute(in frame: Compute.Frame) async throws -> JSON? {
        let lhs = try await $lhs.compute(in: frame)
        let rhs = try await $rhs.compute(in: frame)
        if let lhs = lhs.string {
            guard let rhs = rhs.string else {
                throw JSONError("contains rhs must be a string when lhs is a string")
            }
            return .bool(lhs.contains(rhs))
        }
        if let lhs = lhs.array {
            return .bool(lhs.contains(rhs))
        }
        throw JSONError("contains lhs must be a string or array")
    }
}
