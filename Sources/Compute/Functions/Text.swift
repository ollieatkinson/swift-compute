extension Keyword {
    public struct Text: Codable, Equatable, Sendable {
        public static let name = "text"

        public let from: From

        public init(from: From) {
            self.from = from
        }

        public struct From: Codable, Equatable, Sendable {
            public let joining: Joining?

            public init(joining: Joining? = nil) {
                self.joining = joining
            }
        }

        public struct Joining: Codable, Equatable, Sendable {
            public let array: JSON
            public let separator: JSON?
            public let terminator: JSON?

            public init(array: JSON, separator: JSON? = nil, terminator: JSON? = nil) {
                self.array = array
                self.separator = separator
                self.terminator = terminator
            }
        }
    }
}

extension Keyword.Text: ComputeKeyword {
    public func compute(in frame: ComputeFrame) async throws -> JSON? {
        if let joining = from.joining {
            return try await joining.compute(in: frame["from", "joining"])
        }
        throw JSONError("Expected text formatter")
    }
}
extension Keyword.Text.Joining {
    func compute(in frame: ComputeFrame) async throws -> JSON {
        let array = try await array.compute(frame: frame["array"])
        let separatorValue = try await separator?.compute(frame: frame["separator"])
        let terminatorValue = try await terminator?.compute(frame: frame["terminator"])
        guard case .array(let values) = array else {
            throw JSONError("text.joining expected an array")
        }
        let strings = try values.map { try $0.decode(String.self) }
        let separator = try separatorValue?.decode(String.self) ?? ""
        let terminator = try terminatorValue?.decode(String.self) ?? ""
        return .string(strings.joined(separator: separator).appending(terminator))
    }
}
