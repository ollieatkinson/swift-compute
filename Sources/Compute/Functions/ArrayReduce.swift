extension Keyword {
    public struct ArrayReduce: Codable, Equatable, Sendable {
        public static let name = "array_reduce"

        public let array: JSON
        public let initial: JSON
        public let next: JSON

        public init(array: JSON, initial: JSON, next: JSON) {
            self.array = array
            self.initial = initial
            self.next = next
        }
    }
}

extension Keyword.ArrayReduce: ComputeKeyword {

    public func compute(in frame: ComputeFrame) async throws -> JSON? {
        let source = try await array.compute(frame: frame["array"])
        guard case .array(let values) = source else {
            throw JSONError("array_reduce expected an array")
        }
        var accumulator = try await initial.compute(frame: frame["initial"])
        for (index, value) in values.enumerated() {
            let item: JSON = [
                "accumulator": accumulator,
                "index": .int(index),
                "item": value,
            ]
            accumulator = try await next.compute(frame: frame[item: item, "next", .index(index)])
        }
        return accumulator
    }
}
