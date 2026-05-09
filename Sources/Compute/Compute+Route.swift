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
        self.init(try JSONPath(from: decoder))
    }

    public func encode(to encoder: Encoder) throws {
        try components.encode(to: encoder)
    }
}
