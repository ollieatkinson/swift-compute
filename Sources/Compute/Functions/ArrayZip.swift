import Algorithms

extension Keyword {
    public struct ArrayZip: Codable, Equatable, Sendable {
        public static let name = "array_zip"

        public let together: JSON
        public let flattened: JSON?

        public init(together: JSON, flattened: JSON? = nil) {
            self.together = together
            self.flattened = flattened
        }
    }
}

extension Keyword.ArrayZip: ComputeKeyword {
    public func compute(in frame: ComputeFrame) async throws -> JSON? {
        let together = try await together.compute(frame: frame["together"])
        guard case .array(let values) = together else {
            throw JSONError("array_zip expected an array of arrays")
        }
        let arrays = try values.map { value -> [JSON] in
            guard case .array(let array) = value else {
                throw JSONError("array_zip expected an array of arrays")
            }
            return array
        }
        guard let count = arrays.map(\.count).min(), count > 0 else {
            return .array([])
        }
        let zipped = (0..<count).flatMap { index in arrays.map { $0[index] } }
        if try await flattened?.compute(frame: frame["flattened"]).decode(Bool.self) ?? false {
            return .array(zipped)
        }
        return .array(zipped.chunks(ofCount: arrays.count).map { JSON.array(Array($0)) })
    }
}
