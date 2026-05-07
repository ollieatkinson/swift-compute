extension Compute.Keyword {
    public struct Text: Codable, Equatable, Sendable {
        public static let name = "text"

        public let from: From

        public struct From: Codable, Equatable, Sendable {
            public let joining: Joining?
        }

        public struct Joining: Codable, Equatable, Sendable {
            @Computed public var array: JSON
            @Computed public var separator: JSON?
            @Computed public var terminator: JSON?
        }
    }
}

extension Compute.Keyword.Text: Compute.KeywordDefinition {
    public func compute(in frame: Compute.Frame) async throws -> JSON? {
        if let joining = from.joining {
            return try await joining.compute(in: frame)
        }
        throw JSONError("Expected text formatter")
    }
}
extension Compute.Keyword.Text.Joining {
    func compute(in frame: Compute.Frame) async throws -> JSON {
        let array = try await $array.compute(in: frame)
        let separatorValue = try await $separator.compute(in: frame)
        let terminatorValue = try await $terminator.compute(in: frame)
        guard case .array(let values) = array else {
            throw JSONError("text.joining expected an array")
        }
        let strings = try values.map { try $0.decode(String.self) }
        let separator = try separatorValue?.decode(String.self) ?? ""
        let terminator = try terminatorValue?.decode(String.self) ?? ""
        return .string(strings.joined(separator: separator).appending(terminator))
    }
}
