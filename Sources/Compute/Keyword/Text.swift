import _JSON
extension Compute.Keyword {
    public struct Text: Codable, Equatable, Sendable {
        public static let name = "text"

        public let from: From

        public struct From: Codable, Equatable, Sendable {
            public let joining: Joining?
        }

        public struct Joining: Codable, Equatable, Sendable {
            @Computed public var array: [String]
            @Computed public var separator: String?
            @Computed public var terminator: String?
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
        let separator = try await $separator.compute(in: frame) ?? ""
        let terminator = try await $terminator.compute(in: frame) ?? ""
        return .string(array.joined(separator: separator).appending(terminator))
    }
}
