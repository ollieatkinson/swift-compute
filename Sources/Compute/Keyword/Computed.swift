@propertyWrapper
public struct Computed<Value: Codable & Sendable>: Codable, Sendable {
    public private(set) var wrappedValue: Value
    private let route: [Compute.Route.Component]

    public var projectedValue: Computed<Value> {
        self
    }

    public init(wrappedValue: Value, route: Compute.Route.Component) {
        self.init(wrappedValue: wrappedValue, route: [route])
    }

    public init(wrappedValue: Value, route: [Compute.Route.Component]) {
        self.wrappedValue = wrappedValue
        self.route = route
    }

    public init(from decoder: Decoder) throws {
        self.wrappedValue = try Value(from: decoder)
        self.route = decoder.codingPath.map(Computed.component(from:))
    }

    public func encode(to encoder: Encoder) throws {
        try wrappedValue.encode(to: encoder)
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
}

extension Computed: Equatable where Value: Equatable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.wrappedValue == rhs.wrappedValue
    }
}

public extension Computed where Value == JSON {
    func compute(
        in frame: Compute.Frame,
        item: JSON? = nil,
        appending suffix: Compute.Route.Component...
    ) async throws -> JSON {
        try await wrappedValue.compute(frame: field(in: frame, item: item, appending: suffix))
    }
}

public extension Computed where Value == JSON? {
    func compute(
        in frame: Compute.Frame,
        item: JSON? = nil,
        appending suffix: Compute.Route.Component...
    ) async throws -> JSON? {
        try await wrappedValue?.compute(frame: field(in: frame, item: item, appending: suffix))
    }
}

public extension Computed where Value == [String: JSON]? {
    func compute(in frame: Compute.Frame) async throws -> [String: JSON]? {
        guard let wrappedValue else { return nil }
        var object: [String: JSON] = [:]
        for key in wrappedValue.keys.sorted() {
            object[key] = try await wrappedValue[key]?.compute(
                frame: field(in: frame, appending: [.key(key)])
            )
        }
        return object
    }
}

public extension KeyedDecodingContainer {
    func decode<Wrapped>(
        _ type: Computed<Wrapped?>.Type,
        forKey key: Key
    ) throws -> Computed<Wrapped?> where Wrapped: Codable & Sendable {
        try decodeIfPresent(type, forKey: key) ?? Computed<Wrapped?>(
            wrappedValue: nil,
            route: codingPath.map(Computed<Wrapped?>.component(from:)) + [.key(key.stringValue)]
        )
    }
}
