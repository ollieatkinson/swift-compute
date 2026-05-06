extension Keyword {
    public struct Error: Codable, Equatable, Sendable {
        public static let name = "error"

        public let message: JSON

        public init(message: JSON) {
            self.message = message
        }
    }
}

extension Keyword.Error: ComputeKeyword {
    public func compute() throws -> JSON {
        throw JSONError(try message.decode(String.self))
    }
}
