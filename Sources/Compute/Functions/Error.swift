extension Keyword {
    public struct Error: Codable, Equatable, Sendable {
        public static let name = "error"

        @Computed public var message: JSON
    }
}

extension Keyword.Error: ComputeKeyword {
    public func compute(in frame: ComputeFrame) async throws -> JSON? {
        let message = try await $message.compute(in: frame)
        throw JSONError(try message.decode(String.self))
    }
}
