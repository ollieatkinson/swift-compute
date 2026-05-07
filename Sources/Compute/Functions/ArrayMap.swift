extension Keyword {
    public struct ArrayMap: Codable, Equatable, Sendable {
        public let over: JSON
        public let copy: [Keyword.Map.Copy]?
        public let into_self: JSON?
        public let flattened: JSON?

        public init(over: JSON, copy: [Keyword.Map.Copy]? = nil, into_self: JSON? = nil, flattened: JSON? = nil) {
            self.over = over
            self.copy = copy
            self.into_self = into_self
            self.flattened = flattened
        }
    }
}

extension Keyword.ArrayMap: ComputeKeyword {
    public static let name = "array_map"

    public func compute(in frame: ComputeFrame) async throws -> JSON? {
        let source = try await over.compute(frame: frame["over"])
        guard case .array(let values) = source else {
            throw JSONError("array_map expected an array")
        }
        var mapped: [JSON] = []
        let intoSelf = try await into_self?.compute(frame: frame["into_self"]).decode(Bool.self) ?? false
        for (index, value) in values.enumerated() {
            if let copy {
                let map = Keyword.Map(src: value, dst: intoSelf ? value : .object([:]), copy: copy)
                mapped.append(try await map.compute(
                    in: frame[item: value, "over", .index(index)]
                ) ?? .null)
            } else {
                mapped.append(value)
            }
        }
        let shouldFlatten = try await flattened?.compute(frame: frame["flattened"]).decode(Bool.self) ?? false
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
