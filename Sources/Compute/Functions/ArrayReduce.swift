extension Keyword {
    public struct ArrayReduce: Codable, Equatable, Sendable {
        public static let name = "array_reduce"

        @Computed public var array: JSON
        @Computed public var initial: JSON
        @Computed public var next: JSON
    }
}

extension Keyword.ArrayReduce: ComputeKeyword {

    public func compute(in frame: ComputeFrame) async throws -> JSON? {
        let source = try await $array.compute(in: frame)
        guard case .array(let values) = source else {
            throw JSONError("array_reduce expected an array")
        }
        var accumulator = try await $initial.compute(in: frame)
        for (index, value) in values.enumerated() {
            let item: JSON = [
                "accumulator": accumulator,
                "index": .int(index),
                "item": value,
            ]
            accumulator = try await $next.compute(in: frame, item: item, appending: .index(index))
        }
        return accumulator
    }
}
