extension Keyword {
    public struct This: Codable, Equatable, Sendable {
        @Computed public var value: JSON
        @Computed public var condition: JSON?
    }
}

extension Keyword.This: ComputeKeyword {
    public static let name = "this"

    public func compute(in frame: ComputeFrame) async throws -> JSON? {
        let condition = try await $condition.compute(in: frame)?.decode(Bool.self) ?? true
        guard condition else { return nil }
        return try await $value.compute(in: frame)
    }
}
