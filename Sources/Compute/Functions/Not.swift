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

extension Not: ComputeKeyword {
    public static let keyword = "not"

    public func compute() throws -> JSON {
        .bool(!(try value.decode(Bool.self)))
    }
}
