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
    public func compute(in frame: ComputeFrame) async throws -> JSON? {
        let message = try await message.compute(frame: frame["message"])
        throw JSONError(try message.decode(String.self))
    }
}
