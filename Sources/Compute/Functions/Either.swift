extension Keyword {
    public struct Either: Equatable, Sendable {
        public let branches: [This]

        public init(_ branches: [This]) {
            self.branches = branches
        }
    }
}

extension Keyword.Either: Codable {
    public init(from decoder: Decoder) throws {
        self.init(try [Keyword.This](from: decoder))
    }

    public func encode(to encoder: Encoder) throws {
        try branches.encode(to: encoder)
    }
}

extension Keyword.Either: ComputeKeyword {
    public static let name = "either"

    public func compute(in frame: ComputeFrame) async throws -> JSON? {
        for (index, branch) in branches.indexed() {
            let condition = try await branch.condition?
                .compute(frame: frame[.index(index), "condition"])
                .decode(Bool.self) ?? true
            guard condition else { continue }
            return try await branch.value.compute(frame: frame[.index(index), "value"])
        }
        return nil
    }
}
