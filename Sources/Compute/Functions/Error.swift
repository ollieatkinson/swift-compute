extension Compute.Keywords {
    public struct Error: Codable, Equatable, Sendable {
        public static let name = "error"

        @Computed public var message: JSON
    }
}

extension Compute.Keywords.Error: Compute.Keyword {
    public func compute(in frame: Compute.Frame) async throws -> JSON? {
        let message = try await $message.compute(in: frame)
        throw JSONError(try message.decode(String.self))
    }
}
