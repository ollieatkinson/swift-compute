import _JSON
extension Compute.Keyword {
    public struct Item: Equatable, Sendable {
        public let path: [Compute.Route.Component]

        public init(_ path: [Compute.Route.Component]) {
            self.path = path
        }
    }
}

extension Compute.Keyword.Item: Codable {
    public init(from decoder: Decoder) throws {
        var container = try decoder.unkeyedContainer()
        var path: [Compute.Route.Component] = []
        while !container.isAtEnd {
            path.append(try container.decode(Compute.Route.Component.self))
        }
        self.init(path)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.unkeyedContainer()
        for component in path {
            switch component {
            case .key(let key):
                try container.encode(key)
            case .index(let index):
                try container.encode(index)
            }
        }
    }
}

extension Compute.Keyword.Item: Compute.KeywordDefinition {
    public static let name = "item"

    public func compute(in frame: Compute.Frame) async throws -> JSON? {
        let source = frame.context.item ?? .null
        return source.value(at: Compute.Route(path)) ?? .null
    }
}
