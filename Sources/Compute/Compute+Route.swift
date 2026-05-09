import _JSON
extension Compute {
    public struct Route: Hashable, Sendable, ExpressibleByArrayLiteral {
        public typealias Component = CodingIndex

        public static let root = Route()

        public let components: JSONPath

        public init(_ components: JSONPath = []) {
            self.components = components
        }

        public init(arrayLiteral elements: Component...) {
            self.init(elements)
        }

        public func appending(_ component: Component) -> Route {
            Route(components + [component])
        }

        subscript(components: Component...) -> Route {
            appending(contentsOf: components)
        }

        public func appending(contentsOf components: [Component]) -> Route {
            Route(self.components + components)
        }

        public var path: [String] {
            components.map(\.stringValue)
        }
    }
}

extension Compute.Route: Codable {
    public init(from decoder: Decoder) throws {
        var container = try decoder.unkeyedContainer()
        var components: JSONPath = []
        while !container.isAtEnd {
            components.append(try container.decode(Component.self))
        }
        self.init(components)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.unkeyedContainer()
        for component in components {
            try container.encode(component)
        }
    }
}
