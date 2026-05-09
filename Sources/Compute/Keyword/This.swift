import _JSON
extension Compute.Keyword {
    public struct This: Codable, Equatable, Sendable {
        @Computed public var value: JSON
        @Computed public var condition: Bool?
    }
}

extension Compute.Keyword.This: Compute.KeywordDefinition {
    public static let name = "this"

    public func compute(in frame: Compute.Frame) async throws -> JSON? {
        let condition = try await $condition.compute(in: frame) ?? true
        guard condition else { return nil }
        return try await $value.compute(in: frame)
    }
}
