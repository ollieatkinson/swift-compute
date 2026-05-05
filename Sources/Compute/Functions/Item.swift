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

extension Item: DirectComputeKeyword {
    static func computeDirectly(from input: JSON) throws -> JSON {
        guard case .array(let components) = input else {
            return try JSON.decoded(Item.self, from: input).compute()
        }
        let path = try components.map { component -> ComputeRoute.Component in
            switch component {
            case .string(let key):
                return .key(key)
            case .int(let index):
                return .index(index)
            default:
                return try component.decode(ComputeRoute.Component.self)
            }
        }
        let source = ComputeTaskLocal.context.item ?? .null
        return source.routeValue(at: ComputeRoute(path)) ?? .null
    }
}
