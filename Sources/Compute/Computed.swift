@propertyWrapper
public struct Computed<Value: Codable & Sendable>: Codable, Sendable {
    public private(set) var rawValue: JSON
    private let route: [Compute.Route.Component]

    public var wrappedValue: Value { fatalError("Value is only accessible by computed(in: frame)") }

    public var projectedValue: Computed<Value> {
        self
    }

    public init(rawValue: JSON, route: Compute.Route.Component) {
        self.init(rawValue: rawValue, route: [route])
    }

    public init(rawValue: JSON, route: [Compute.Route.Component]) {
        self.rawValue = rawValue
        self.route = route
    }

    public init(from decoder: Decoder) throws {
        self.rawValue = try JSON(from: decoder)
        self.route = decoder.codingPath.map(Computed.component(from:))
    }

    public func encode(to encoder: Encoder) throws {
        try rawValue.encode(to: encoder)
    }

    fileprivate static func component(from key: any CodingKey) -> Compute.Route.Component {
        if let index = key.intValue {
            return .index(index)
        }
        return .key(key.stringValue)
    }

    fileprivate func field(
        in frame: Compute.Frame,
        item: JSON? = nil,
        appending suffix: [Compute.Route.Component] = []
    ) throws -> Compute.Frame {
        guard !route.isEmpty else {
            throw JSONError("Computed property is missing a route")
        }
        let context = item.map(frame.context.with(item:)) ?? frame.context
        let depth = item == nil ? frame.depth : frame.depth + 1
        return Compute.Frame(
            context: context,
            runtime: frame.runtime,
            route: frame.route.appending(contentsOf: route + suffix),
            depth: depth
        )
    }

    private static func decoded(_ value: JSON) throws -> Value {
        if value == .null, let optional = Value.self as? OptionalProtocol.Type {
            return optional.nilValue as! Value
        }
        return try value.decode(Value.self)
    }
}

private protocol OptionalProtocol {
    static var nilValue: Any { get }
}

extension Optional: OptionalProtocol {
    static var nilValue: Any {
        Optional<Wrapped>.none as Any
    }
}

extension Computed: Equatable where Value: Equatable { }

public extension Computed {
    func compute(
        in frame: Compute.Frame,
        item: JSON? = nil,
        appending suffix: Compute.Route.Component...
    ) async throws -> Value {
        let computed = try await rawValue.compute(
            frame: field(in: frame, item: item, appending: suffix)
        )
        return try Self.decoded(computed)
    }
}

public extension KeyedDecodingContainer {
    func decode<Wrapped>(
        _ type: Computed<Wrapped?>.Type,
        forKey key: Key
    ) throws -> Computed<Wrapped?> where Wrapped: Codable & Sendable {
        try decodeIfPresent(type, forKey: key) ?? Computed<Wrapped?>(
            rawValue: nil,
            route: codingPath.map(Computed<Wrapped?>.component(from:)) + [.key(key.stringValue)]
        )
    }
}
