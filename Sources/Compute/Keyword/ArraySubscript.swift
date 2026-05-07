extension Compute.Keyword {
    public struct ArraySubscript: Codable, Equatable, Sendable {
        public static let name = "array_subscript"

        @Computed public var of: [JSON]
        @Computed public var index: Int
        @Computed public var reversed: Bool?
    }
}

extension Compute.Keyword.ArraySubscript: Compute.KeywordDefinition {
    public func compute(in frame: Compute.Frame) async throws -> JSON? {
        let values = try await $of.compute(in: frame)
        let reversed = try await $reversed.compute(in: frame) ?? false
        let source = reversed ? Array(values.reversed()) : values
        let index = try await $index.compute(in: frame)
        guard source.indices.contains(index) else {
            return .null
        }
        return source[index]
    }
}
