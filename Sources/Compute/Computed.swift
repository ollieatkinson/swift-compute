import _JSON
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

    func field(
        in frame: Compute.Frame,
        item: JSON? = nil,
        appending suffix: [Compute.Route.Component] = []
    ) throws -> Compute.Frame {
        guard !route.isEmpty else {
            throw JSONError("Computed property is missing a route")
        }
        let context = item.map(frame.context.with(item:)) ?? frame.context
        return Compute.Frame(
            context: context,
            runtime: frame.runtime,
            route: frame.route.appending(contentsOf: route + suffix),
            depth: frame.depth,
            references: frame.references
        )
    }
}

private func decodeComputedValue<Value: Decodable>(_ value: JSON, as type: Value.Type) throws -> Value {
    if let optional = Value.self as? OptionalProtocol.Type {
        return try optional.decoded(value) as! Value
    }
    return try value.decode(Value.self)
}

private protocol OptionalProtocol {
    static func decoded(_ value: JSON) throws -> Self
}

extension Optional: OptionalProtocol where Wrapped: Decodable {
    static func decoded(_ value: JSON) throws -> Self {
        if value.isNull { return nil }
        // Decode the present wrapped value directly. AnyDecoder's Optional
        // conversion otherwise turns a malformed value into an absent input.
        return .some(try decodeComputedValue(value, as: Wrapped.self))
    }
}

extension Computed: Equatable where Value: Equatable { }

public extension Computed {
    func compute(
        in frame: Compute.Frame,
        item: JSON? = nil,
        appending suffix: Compute.Route.Component...
    ) async throws -> Value {
        let field = try field(in: frame, item: item, appending: suffix)
        let computed = try await rawValue.compute(in: field)
        do { return try decodeComputedValue(computed, as: Value.self) }
        catch { throw JSONError(error, path: field.route.path) }
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
