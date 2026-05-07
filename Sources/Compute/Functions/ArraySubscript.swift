extension Keyword {
    public struct ArraySubscript: Codable, Equatable, Sendable {
        public static let name = "array_subscript"

        public let of: JSON
        public let index: JSON
        public let reversed: JSON?

        public init(of: JSON, index: JSON, reversed: JSON? = nil) {
            self.of = of
            self.index = index
            self.reversed = reversed
        }
    }
}

extension Keyword.ArraySubscript: ComputeKeyword {
    public func compute(in frame: ComputeFrame) async throws -> JSON? {
        let of = try await of.compute(frame: frame["of"])
        guard case .array(let values) = of else {
            throw JSONError("array_subscript expected an array")
        }
        let reversed = try await reversed?.compute(frame: frame["reversed"]).decode(Bool.self) ?? false
        let source = reversed ? Array(values.reversed()) : values
        let index = try await index.compute(frame: frame["index"]).decode(Int.self)
        guard source.indices.contains(index) else {
            return .null
        }
        return source[index]
    }
}
