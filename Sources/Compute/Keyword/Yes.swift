extension Compute.Keyword {
    public struct Yes: Codable, Equatable, Sendable {
        @Computed public var `if`: [Bool]?
        @Computed public var unless: [Bool]?
    }
}

extension Compute.Keyword.Yes: Compute.KeywordDefinition {
    public static let name = "yes"

    public func compute(in frame: Compute.Frame) async throws -> JSON? {
        let conditions = try await $if.compute(in: frame) ?? []
        let exceptions = try await $unless.compute(in: frame) ?? []
        let satisfied = conditions.allSatisfy(\.self)
        let blocked = exceptions.contains(true)
        return .bool(satisfied && !blocked)
    }
}
