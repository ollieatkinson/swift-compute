public struct Item: Equatable, Sendable {
    public let path: [ComputeRoute.Component]

    public init(_ path: [ComputeRoute.Component]) {
        self.path = path
    }
}

extension Item: Codable {
    public init(from decoder: Decoder) throws {
        var container = try decoder.unkeyedContainer()
        var path: [ComputeRoute.Component] = []
        while !container.isAtEnd {
            path.append(try container.decode(ComputeRoute.Component.self))
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

extension Item: ComputeKeyword {
    public static let keyword = "item"

    public func compute() throws -> JSON {
        let source = ComputeTaskLocal.context.item ?? .null
        return source.routeValue(at: ComputeRoute(path)) ?? .null
    }
}
