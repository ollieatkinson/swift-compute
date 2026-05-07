import Algorithms

extension Compute.Keyword {
    public struct ArrayZip: Codable, Equatable, Sendable {
        public static let name = "array_zip"

        @Computed public var together: [[JSON]]
        @Computed public var flattened: Bool?
    }
}

extension Compute.Keyword.ArrayZip: Compute.KeywordDefinition {
    public func compute(in frame: Compute.Frame) async throws -> JSON? {
        let arrays = try await $together.compute(in: frame)
        guard let count = arrays.map(\.count).min(), count > 0 else {
            return .array([])
        }
        let zipped = (0..<count).flatMap { index in arrays.map { $0[index] } }
        if try await $flattened.compute(in: frame) ?? false {
            return .array(zipped)
        }
        return .array(zipped.chunks(ofCount: arrays.count).map { JSON.array(Array($0)) })
    }
}
