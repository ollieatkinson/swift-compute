extension Keyword {
    public struct Map: Codable, Equatable, Sendable {
        @Computed public var src: JSON
        @Computed public var dst: JSON?
        public let copy: [Copy]?

        public struct Copy: Codable, Equatable, Sendable {
            @Computed public var value: JSON
            public let to: [ComputeRoute.Component]
        }
    }
}

extension Keyword.Map: ComputeKeyword {
    public static let name = "map"

    public func compute(in frame: ComputeFrame) async throws -> JSON? {
        let source = try await $src.compute(in: frame)
        var destination = try await $dst.compute(in: frame, item: source) ?? source
        for copy in copy ?? [] {
            let value = try await copy.$value.compute(in: frame, item: source)
            try destination.set(value, at: ComputeRoute(copy.to))
        }
        return destination
    }
}
