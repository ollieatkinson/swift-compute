extension Keyword {
    public struct Yes: Codable, Equatable, Sendable {
        @Computed public var `if`: JSON?
        @Computed public var unless: JSON?
    }
}

extension Keyword.Yes: ComputeKeyword {
    public static let name = "yes"

    public func compute(in frame: ComputeFrame) async throws -> JSON? {
        let conditions = try await $if.compute(in: frame)?.asList() ?? []
        let exceptions = try await $unless.compute(in: frame)?.asList() ?? []
        let satisfied = try conditions.allSatisfy { try $0.decode(Bool.self) }
        let blocked = try exceptions.contains { try $0.decode(Bool.self) }
        return .bool(satisfied && !blocked)
    }
}
