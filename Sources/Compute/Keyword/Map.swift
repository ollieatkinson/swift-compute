import _JSON
extension Compute.Keyword {
    public struct Map: Codable, Equatable, Sendable {
        @Computed public var src: JSON
        @Computed public var dst: JSON?
        @Computed public var copy: [Copy]?

        public struct Copy: Codable, Equatable, Sendable {
            @Computed public var value: JSON
            public let to: [Compute.Route.Component]
            public let from: [Compute.Route.Component]?
            public let required: Bool

            private enum CodingKeys: String, CodingKey { case value, to, from, required }

            public init(from decoder: any Decoder) throws {
                let fields = try decoder.container(keyedBy: CodingKeys.self)
                to = try fields.decode([Compute.Route.Component].self, forKey: .to)
                from = try fields.decodeIfPresent([Compute.Route.Component].self, forKey: .from)
                required = try fields.decodeIfPresent(Bool.self, forKey: .required) ?? false
                guard (from != nil) != fields.contains(.value) else {
                    throw DecodingError.dataCorruptedError(forKey: .value, in: fields,
                        debugDescription: "A map copy needs either from or value")
                }
                _value = fields.contains(.value) ? try fields.decode(Computed<JSON>.self, forKey: .value)
                    : Computed(rawValue: .null, route: .key("value"))
            }

            public func encode(to encoder: any Encoder) throws {
                var fields = encoder.container(keyedBy: CodingKeys.self)
                try fields.encode(to, forKey: .to)
                if let from { try fields.encode(from, forKey: .from) }
                else { try fields.encode(_value, forKey: .value) }
                if required { try fields.encode(true, forKey: .required) }
            }

            // Copy values are templates evaluated once in the source item's scope.
            // Resolve the plan's paths/flags without eagerly executing those templates.
            static func plan(_ plan: Computed<[Self]?>, in frame: Compute.Frame,
                item: JSON, appending suffix: [Compute.Route.Component] = []) async throws -> [Self]? {
                let field = try plan.field(in: frame, item: item, appending: suffix)
                guard !plan.rawValue.isNull else { return nil }
                guard let entries = plan.rawValue.array else {
                    let resolved = try await field.compute(plan.rawValue)
                    return resolved.isNull ? nil : try resolved.decode([Self].self)
                }
                var resolved: [JSON] = []
                for (index, entry) in entries.enumerated() {
                    guard var fields = entry.object else { throw JSONError("Expected a map copy object") }
                    for key in fields.keys.sorted() where key != "value" {
                        fields[key] = try await field[.index(index), .key(key)].compute(fields[key]!)
                    }
                    resolved.append(.object(fields))
                }
                return try JSON.array(resolved).decode([Self].self)
            }

            func compute(from source: JSON, in frame: Compute.Frame) async throws -> JSON? {
                if let from {
                    if let value = source.value(at: from) { return value }
                    if required { throw JSONError("Missing map source", path: from.map(\.stringValue)) }
                    return .none
                }
                return try await $value.compute(in: frame, item: source)
            }
        }
    }
}

extension Compute.Keyword.Map: Compute.OpaqueOutputKeywordDefinition {
    public static let name = "map"

    public func compute(in frame: Compute.Frame) async throws -> JSON? {
        let source = try await $src.compute(in: frame)
        var destination = try await $dst.compute(in: frame, item: source) ?? source
        for copy in try await Copy.plan($copy, in: frame, item: source) ?? [] {
            if let value = try await copy.compute(from: source, in: frame["copy"]) {
                try destination.set(value, at: Compute.Route(copy.to))
            }
        }
        return destination
    }
}
