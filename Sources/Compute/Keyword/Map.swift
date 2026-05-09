import _JSON
extension Compute.Keyword {
    public struct Map: Codable, Equatable, Sendable {
        @Computed public var src: JSON
        @Computed public var dst: JSON?
        @Computed public var copy: [Copy]?

        public struct Copy: Codable, Equatable, Sendable {
            @Computed public var value: JSON
            public let to: [Compute.Route.Component]
        }
    }
}

extension Compute.Keyword.Map: Compute.KeywordDefinition {
    public static let name = "map"

    public func compute(in frame: Compute.Frame) async throws -> JSON? {
        let source = try await $src.compute(in: frame)
        var destination = try await $dst.compute(in: frame, item: source) ?? source
        for copy in try await $copy.compute(in: frame, item: source) ?? [] {
            let value = try await copy.$value.compute(in: frame, item: source)
            try destination.set(value, at: Compute.Route(copy.to))
        }
        return destination
    }
}
