extension Compute.Keyword {
    public struct ArrayMap: Codable, Equatable, Sendable {
        @Computed public var over: JSON
        public let copy: [Compute.Keyword.Map.Copy]?
        @Computed public var into_self: JSON?
        @Computed public var flattened: JSON?
    }
}

extension Compute.Keyword.ArrayMap: Compute.KeywordDefinition {
    public static let name = "array_map"

    public func compute(in frame: Compute.Frame) async throws -> JSON? {
        let source = try await $over.compute(in: frame)
        guard case .array(let values) = source else {
            throw JSONError("array_map expected an array")
        }
        var mapped: [JSON] = []
        let intoSelf = try await $into_self.compute(in: frame)?.decode(Bool.self) ?? false
        for (index, value) in values.enumerated() {
            if let copies = copy {
                var destination: JSON = intoSelf ? value : .object([:])
                for copy in copies {
                    let copied = try await copy.$value.compute(
                        in: frame["over", .index(index)],
                        item: value
                    )
                    try destination.set(copied, at: Compute.Route(copy.to))
                }
                mapped.append(destination)
            } else {
                mapped.append(value)
            }
        }
        let shouldFlatten = try await $flattened.compute(in: frame)?.decode(Bool.self) ?? false
        return try Self.mapped(over: .array(mapped), flattened: .bool(shouldFlatten))
    }

    private static func mapped(over: JSON, flattened: JSON?) throws -> JSON {
        guard case .array(let values) = over else {
            throw JSONError("array_map expected an array")
        }
        let shouldFlatten = try flattened?.decode(Bool.self) ?? false
        if shouldFlatten {
            return .array(values.flatMap { value in
                if case .array(let values) = value {
                    return values
                }
                return [value]
            })
        }
        return .array(values)
    }
}
