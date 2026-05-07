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
    public func compute(in frame: ComputeFrame) async throws -> JSON? {
        let of = try await of.compute(frame: frame["of"])
        guard case .array(let values) = of else {
            throw JSONError("array_slice expected an array")
        }
        let reversed = try await reversed?.compute(frame: frame["reversed"]).decode(Bool.self) ?? false
        let source = reversed ? Array(values.reversed()) : values
        let lowerValue = try await from?.compute(frame: frame["from"]).decode(Int.self)
        let upperValue = try await to?.compute(frame: frame["to"]).decode(Int.self)
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
