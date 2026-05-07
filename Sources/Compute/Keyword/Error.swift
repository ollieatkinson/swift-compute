extension Compute.Keyword {
    public struct Error: Codable, Equatable, Sendable {
        public static let name = "error"

        @Computed public var message: String
    }
}

extension Compute.Keyword.Error: Compute.KeywordDefinition {
    public func compute(in frame: Compute.Frame) async throws -> JSON? {
        let message = try await $message.compute(in: frame)
        throw JSONError(message)
    }
}
