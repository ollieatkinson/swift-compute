extension Keyword {
    public struct Map: Codable, Equatable, Sendable {
        public let src: JSON
        public let dst: JSON?
        public let copy: [Copy]?

        public init(src: JSON, dst: JSON? = nil, copy: [Copy]? = nil) {
            self.src = src
            self.dst = dst
            self.copy = copy
        }

        public struct Copy: Codable, Equatable, Sendable {
            public let value: JSON
            public let to: [ComputeRoute.Component]

            public init(value: JSON, to: [String]) {
                self.init(value: value, to: to.map(ComputeRoute.Component.key))
            }

            public init(value: JSON, to: [ComputeRoute.Component]) {
                self.value = value
                self.to = to
            }
        }
    }
}

extension Keyword.Map: ComputeKeyword {
    public static let name = "map"

    public func compute(in frame: ComputeFrame) async throws -> JSON? {
        let source = try await src.compute(frame: frame["src"])
        var destination: JSON
        if let dst {
            destination = try await dst.compute(frame: frame[item: source, "dst"])
        } else {
            destination = source
        }
        var copies: [Keyword.Map.Copy] = []
        for (index, copy) in (copy ?? []).enumerated() {
            let value = try await copy.value.compute(
                frame: frame[item: source, "copy", .index(index), "value"]
            )
            copies.append(Keyword.Map.Copy(value: value, to: copy.to))
        }
        return try Self.mapped(src: source, dst: destination, copy: copies)
    }

    private static func mapped(src: JSON, dst: JSON?, copy: [Copy]?) throws -> JSON {
        var destination = dst ?? src
        for copy in copy ?? [] {
            try destination.set(copy.value, at: ComputeRoute(copy.to))
        }
        return destination
    }
}
