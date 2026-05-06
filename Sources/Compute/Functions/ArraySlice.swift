extension Keyword {
    public struct ArraySlice: Codable, Equatable, Sendable {
        public static let name = "array_slice"

        public let of: JSON
        public let from: JSON?
        public let to: JSON?
        public let reversed: JSON?

        public init(of: JSON, from: JSON? = nil, to: JSON? = nil, reversed: JSON? = nil) {
            self.of = of
            self.from = from
            self.to = to
            self.reversed = reversed
        }
    }
}

extension Keyword.ArraySlice: ComputeKeyword {
    public func compute() throws -> JSON {
        guard case .array(let values) = of else {
            throw JSONError("array_slice expected an array")
        }
        let source = try (reversed?.decode(Bool.self) ?? false) ? Array(values.reversed()) : values
        let lower = clamp(try from?.decode(Int.self) ?? source.startIndex, to: source.indices)
        let upper = clamp(try to?.decode(Int.self) ?? source.endIndex, to: source.indices)
        guard lower <= upper else {
            return .array([])
        }
        return .array(Array(source[lower..<upper]))
    }

    private func clamp(_ value: Int, to indices: Range<Int>) -> Int {
        min(max(value, indices.lowerBound), indices.upperBound)
    }
}
