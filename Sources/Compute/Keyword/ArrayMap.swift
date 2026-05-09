import _JSON
extension Compute.Keyword {
    public struct ArrayMap: Codable, Equatable, Sendable {
        @Computed public var over: [JSON]
        @Computed public var copy: [Copy]?
        @Computed public var into_self: Bool?
        @Computed public var flattened: Bool?

        public struct Copy: Codable, Equatable, Sendable {
            @Computed public var value: JSON
            public let to: [Compute.Route.Component]
        }
    }
}

extension Compute.Keyword.ArrayMap: Compute.KeywordDefinition {
    public static let name = "array_map"

    public func compute(in frame: Compute.Frame) async throws -> JSON? {
        let values = try await $over.compute(in: frame)
        var mapped: [JSON] = []
        let intoSelf = try await $into_self.compute(in: frame) ?? false
        for (index, value) in values.indexed() {
            if let copies = try await $copy.compute(in: frame, item: value, appending: .index(index)) {
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
                if let values = value.array {
                    return values
                }
                return [value]
            })
        }
        return .array(values)
    }
}
