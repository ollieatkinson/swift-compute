extension Keyword {
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

extension Keyword.Not: ComputeKeyword {
    public static let name = "not"

    public func compute(in frame: ComputeFrame) async throws -> JSON? {
        let value = try await value.compute(frame: frame)
        return .bool(!(try value.decode(Bool.self)))
    }
}
