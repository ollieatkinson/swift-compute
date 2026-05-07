extension Compute.Keywords {
    public struct Count: Codable, Equatable, Sendable {
        @Computed public var of: JSON?
    }
}

extension Compute.Keywords.Count: Compute.Keyword {
    public static let name = "count"

    public func compute(in frame: Compute.Frame) async throws -> JSON? {
        let value: JSON
        do {
            value = try await $of.compute(in: frame) ?? .null
        } catch {
            value = .null
        }
        return .int(value.count)
    }
}
