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
        return try (ComputeTaskLocal.context.item ?? .null).routeValue(atPathComponents: components) ?? .null
    }
}

private extension JSON {
    func routeValue(atPathComponents components: [JSON]) throws -> JSON? {
        var current = self
        for component in components {
            switch (component, current) {
            case (.string(let key), .object(let object)):
                guard let value = object[key] else { return nil }
                current = value
            case (.int(let index), .array(let array)):
                guard array.indices.contains(index) else { return nil }
                current = array[index]
            default:
                switch try component.decode(ComputeRoute.Component.self) {
                case .key(let key):
                    guard case .object(let object) = current, let value = object[key] else { return nil }
                    current = value
                case .index(let index):
                    guard case .array(let array) = current, array.indices.contains(index) else { return nil }
                    current = array[index]
                }
            }
        }
        return current
    }
}
