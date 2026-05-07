extension Compute.Keyword {
    public struct Either: Equatable, Sendable {
        public let branches: [This]
    }
}

extension Compute.Keyword.Either: Codable {
    public init(from decoder: Decoder) throws {
        self.branches = try [Compute.Keyword.This](from: decoder)
    }

    public func encode(to encoder: Encoder) throws {
        try branches.encode(to: encoder)
    }
}

extension Compute.Keyword.Either: Compute.KeywordDefinition {
    public static let name = "either"

    public func compute(in frame: Compute.Frame) async throws -> JSON? {
        for branch in branches {
            let condition = try await branch.$condition.compute(in: frame) ?? true
            guard condition else { continue }
            return try await branch.$value.compute(in: frame)
        }
        return nil
    }
}
