extension Compute.Keywords {
    public struct ArraySubscript: Codable, Equatable, Sendable {
        public static let name = "array_subscript"

        @Computed public var of: JSON
        @Computed public var index: JSON
        @Computed public var reversed: JSON?
    }
}

extension Compute.Keywords.ArraySubscript: Compute.Keyword {
    public func compute(in frame: Compute.Frame) async throws -> JSON? {
        let of = try await $of.compute(in: frame)
        guard case .array(let values) = of else {
            throw JSONError("array_subscript expected an array")
        }
        let reversed = try await $reversed.compute(in: frame)?.decode(Bool.self) ?? false
        let source = reversed ? Array(values.reversed()) : values
        let index = try await $index.compute(in: frame).decode(Int.self)
        guard source.indices.contains(index) else {
            return .null
        }
        return source[index]
    }
}
