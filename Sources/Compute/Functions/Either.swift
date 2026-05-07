extension Compute.Keywords {
    public struct Either: Equatable, Sendable {
        public let branches: [This]
    }
}

extension Compute.Keywords.Either: Codable {
    public init(from decoder: Decoder) throws {
        self.branches = try [Compute.Keywords.This](from: decoder)
    }

    public func encode(to encoder: Encoder) throws {
        try branches.encode(to: encoder)
    }
}

extension Compute.Keywords.Either: Compute.Keyword {
    public static let name = "either"

    public func compute(in frame: Compute.Frame) async throws -> JSON? {
        for branch in branches {
            let condition = try await branch.$condition.compute(in: frame)?.decode(Bool.self) ?? true
            guard condition else { continue }
            return try await branch.$value.compute(in: frame)
        }
        return nil
    }
}
