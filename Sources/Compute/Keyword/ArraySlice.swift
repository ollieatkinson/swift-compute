extension Compute.Keyword {
    public struct ArraySlice: Codable, Equatable, Sendable {
        public static let name = "array_slice"

        @Computed public var of: JSON
        @Computed public var from: JSON?
        @Computed public var to: JSON?
        @Computed public var reversed: JSON?
    }
}

extension Compute.Keyword.ArraySlice: Compute.KeywordDefinition {
    public func compute(in frame: Compute.Frame) async throws -> JSON? {
        let of = try await $of.compute(in: frame)
        guard case .array(let values) = of else {
            throw JSONError("array_slice expected an array")
        }
        let reversed = try await $reversed.compute(in: frame)?.decode(Bool.self) ?? false
        let source = reversed ? Array(values.reversed()) : values
        let lowerValue = try await $from.compute(in: frame)?.decode(Int.self)
        let upperValue = try await $to.compute(in: frame)?.decode(Int.self)
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
