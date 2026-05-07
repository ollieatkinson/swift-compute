extension Compute.Keyword {
    public struct ArrayReduce: Codable, Equatable, Sendable {
        public static let name = "array_reduce"

        @Computed public var array: [JSON]
        @Computed public var initial: JSON
        @Computed public var next: JSON
    }
}

extension Compute.Keyword.ArrayReduce: Compute.KeywordDefinition {

    public func compute(in frame: Compute.Frame) async throws -> JSON? {
        let values = try await $array.compute(in: frame)
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
