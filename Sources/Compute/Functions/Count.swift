extension Keyword {
    public struct Count: Codable, Equatable, Sendable {
        @Computed public var of: JSON?
    }
}

extension Keyword.Count: ComputeKeyword {
    public static let name = "count"

    public func compute(in frame: ComputeFrame) async throws -> JSON? {
        let value: JSON
        do {
            value = try await $of.compute(in: frame) ?? .null
        } catch {
            value = .null
        }
        return .int(value.count)
    }
}
