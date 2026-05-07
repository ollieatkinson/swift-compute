extension Keyword {
    public struct This: Codable, Equatable, Sendable {
        public let value: JSON
        public let condition: JSON?

        public init(value: JSON, condition: JSON? = nil) {
            self.value = value
            self.condition = condition
        }
    }
}

extension Keyword.This: ComputeKeyword {
    public static let name = "this"

    public func compute(in frame: ComputeFrame) async throws -> JSON? {
        let condition: Bool
        if let rawCondition = self.condition {
            condition = try await rawCondition.compute(frame: frame["condition"]).decode(Bool.self)
        } else {
            condition = true
        }
        guard condition else { return nil }
        return try await self.value.compute(frame: frame["value"])
    }
}
