extension Compute.Keywords {
    public struct Exists: Codable, Equatable, Sendable {
        @Computed public var value: JSON?
    }
}

extension Compute.Keywords.Exists: Compute.Keyword {
    public static let name = "exists"

    public func compute(in frame: Compute.Frame) async throws -> JSON? {
        let computed: JSON
        do {
            computed = try await $value.compute(in: frame) ?? .null
        } catch {
            computed = .null
        }
        return .bool(computed != .null)
    }
}
