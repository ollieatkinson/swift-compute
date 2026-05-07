extension Compute.Keyword {
    public struct ArrayMap: Codable, Equatable, Sendable {
        @Computed public var over: [JSON]
        public let copy: [Compute.Keyword.Map.Copy]?
        @Computed public var into_self: Bool?
        @Computed public var flattened: Bool?
    }
}

extension Compute.Keyword.ArrayMap: Compute.KeywordDefinition {
    public static let name = "array_map"

    public func compute(in frame: Compute.Frame) async throws -> JSON? {
        let values = try await $over.compute(in: frame)
        var mapped: [JSON] = []
        let intoSelf = try await $into_self.compute(in: frame) ?? false
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
        let shouldFlatten = try await $flattened.compute(in: frame) ?? false
        return Self.mapped(over: mapped, flattened: shouldFlatten)
    }

    private static func mapped(over values: [JSON], flattened: Bool) -> JSON {
        if flattened {
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
