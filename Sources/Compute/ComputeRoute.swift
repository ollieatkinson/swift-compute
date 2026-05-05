public struct ComputeRoute: Hashable, Sendable, ExpressibleByArrayLiteral {
    public enum Component: Hashable, Codable, Sendable, ExpressibleByStringLiteral, ExpressibleByIntegerLiteral {
        case key(String)
        case index(Int)

        public init(stringLiteral value: String) {
            self = .key(value)
        }

        public init(integerLiteral value: Int) {
            self = .index(value)
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            if let index = try? container.decode(Int.self) {
                self = .index(index)
                return
            }
            self = .key(try container.decode(String.self))
        }

        public func encode(to encoder: Encoder) throws {
            var container = encoder.singleValueContainer()
            switch self {
            case .key(let key):
                try container.encode(key)
            case .index(let index):
                try container.encode(index)
            }
        }

        var json: JSON {
            switch self {
            case .key(let key):
                return .string(key)
            case .index(let index):
                return .int(index)
            }
        }
    }

    public static let root = ComputeRoute()

    public let components: [Component]

    public init(_ components: [Component] = []) {
        self.components = components
    }

    public init(arrayLiteral elements: Component...) {
        self.init(elements)
    }

    public func appending(_ component: Component) -> ComputeRoute {
        var components = components
        components.append(component)
        return ComputeRoute(components)
    }

    func appending(_ first: Component, _ second: Component) -> ComputeRoute {
        var components = components
        components.reserveCapacity(components.count + 2)
        components.append(first)
        components.append(second)
        return ComputeRoute(components)
    }

    public var path: [String] {
        components.map { component in
            switch component {
            case .key(let key):
                return key
            case .index(let index):
                return String(index)
            }
        }
    }
}

extension ComputeRoute: Codable {
    public init(from decoder: Decoder) throws {
        var container = try decoder.unkeyedContainer()
        var components: [Component] = []
        while !container.isAtEnd {
            if let index = try? container.decode(Int.self) {
                components.append(.index(index))
            } else {
                components.append(.key(try container.decode(String.self)))
            }
        }
        self.init(components)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.unkeyedContainer()
        for component in components {
            switch component {
            case .key(let key):
                try container.encode(key)
            case .index(let index):
                try container.encode(index)
            }
        }
    }
}
