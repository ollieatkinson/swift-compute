extension Keyword {
    public struct Count: Codable, Equatable, Sendable {
        public let of: JSON?

        public init(of: JSON? = nil) {
            self.of = of
        }
    }
}

extension Keyword.Count: ComputeKeyword {
    public static let name = "count"

    public func compute(in frame: ComputeFrame) async throws -> JSON? {
        let value: JSON
        do {
            value = try await (of ?? .null).compute(frame: frame["of"])
        } catch {
            value = .null
        }
        return .int(value.count)
    }
}
