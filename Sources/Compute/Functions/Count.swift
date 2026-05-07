extension Compute.Keyword {
    public struct Count: Codable, Equatable, Sendable {
        @Computed public var of: JSON?
    }
}

extension Compute.Keyword.Count: Compute.KeywordDefinition {
    public static let name = "count"

    public func compute(in frame: Compute.Frame) async throws -> JSON? {
        let value: JSON
        do {
            value = try await $of.compute(in: frame) ?? .null
        } catch {
            value = .null
        }
        return .int(value.count)
    }
}
