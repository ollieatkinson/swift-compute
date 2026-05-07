extension Compute.Keyword {
    public struct Not: Codable, Equatable, Sendable {
        public let value: JSON

        public init(_ value: JSON) {
            self.value = value
        }

        public init(from decoder: Decoder) throws {
            self.value = try JSON(from: decoder)
        }

        public func encode(to encoder: Encoder) throws {
            try value.encode(to: encoder)
        }
    }
}

extension Compute.Keyword.Not: Compute.KeywordDefinition {
    public static let name = "not"

    public func compute(in frame: Compute.Frame) async throws -> JSON? {
        let value = try await value.compute(frame: frame)
        return .bool(!(try value.decode(Bool.self)))
    }
}
