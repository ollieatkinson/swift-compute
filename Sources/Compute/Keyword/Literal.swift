import _JSON

extension Compute.Keyword {
    /// Returns JSON unchanged, including any nested expressions. This provides
    /// an explicit boundary for deferred data and previously evaluated values.
    public struct Literal: Compute.OpaqueOutputKeywordDefinition {
        public static let name = "literal"
        public let value: JSON

        public init(value: JSON) { self.value = value }

        private enum CodingKeys: String, CodingKey { case value }
        public init(from decoder: any Decoder) throws {
            let values = try decoder.container(keyedBy: CodingKeys.self)
            guard values.contains(.value) else {
                throw DecodingError.keyNotFound(CodingKeys.value, .init(codingPath: decoder.codingPath,
                    debugDescription: "A literal requires a value"))
            }
            value = try values.decode(JSON.self, forKey: .value)
        }

        public func compute(in frame: Compute.Frame) async throws -> JSON? { value }
    }
}
