import Algorithms

extension Keyword {
    public struct ArrayZip: Codable, Equatable, Sendable {
        public static let name = "array_zip"

        @Computed public var together: JSON
        @Computed public var flattened: JSON?
    }
}

extension Keyword.ArrayZip: ComputeKeyword {
    public func compute(in frame: ComputeFrame) async throws -> JSON? {
        let together = try await $together.compute(in: frame)
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
        if try await $flattened.compute(in: frame)?.decode(Bool.self) ?? false {
            return .array(zipped)
        }
        return .array(zipped.chunks(ofCount: arrays.count).map { JSON.array(Array($0)) })
    }
}
