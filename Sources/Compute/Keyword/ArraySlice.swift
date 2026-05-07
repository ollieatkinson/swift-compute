extension Compute.Keyword {
    public struct ArraySlice: Codable, Equatable, Sendable {
        public static let name = "array_slice"

        @Computed public var of: [JSON]
        @Computed public var from: Int?
        @Computed public var to: Int?
        @Computed public var reversed: Bool?
    }
}

extension Compute.Keyword.ArraySlice: Compute.KeywordDefinition {
    public func compute(in frame: Compute.Frame) async throws -> JSON? {
        let values = try await $of.compute(in: frame)
        let reversed = try await $reversed.compute(in: frame) ?? false
        let source = reversed ? Array(values.reversed()) : values
        let lowerValue = try await $from.compute(in: frame)
        let upperValue = try await $to.compute(in: frame)
        let lower = clamp(lowerValue ?? source.startIndex, to: source.indices)
        let upper = clamp(upperValue ?? source.endIndex, to: source.indices)
        guard lower <= upper else {
            return .array([])
        }
        return .array(Array(source[lower..<upper]))
    }

    private func clamp(_ value: Int, to indices: Range<Int>) -> Int {
        min(max(value, indices.lowerBound), indices.upperBound)
    }
}
