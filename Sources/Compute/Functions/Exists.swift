extension Keyword {
    public struct Exists: Codable, Equatable, Sendable {
        public let value: JSON?

        public init(value: JSON? = nil) {
            self.value = value
        }
    }
}

extension Keyword.Exists: ComputeKeyword {
    public static let name = "exists"

    public func compute(in frame: ComputeFrame) async throws -> JSON? {
        let computed: JSON
        do {
            computed = try await (value ?? .null).compute(frame: frame["value"])
        } catch {
            computed = .null
        }
        return .bool(computed != .null)
    }
}
