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

    public func compute() throws -> JSON {
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

extension Keyword.ArrayMap: CustomComputeKeyword {
    func compute(
        context: Compute.Context,
        runtime: ComputeFunctionRuntime,
        route: ComputeRoute,
        depth: Int
    ) async throws -> JSON? {
        let source = try await over.compute(
            context: context,
            runtime: runtime,
            route: route.appending(.key("over")),
            depth: depth
        )
        guard case .array(let values) = source else {
            throw JSONError("array_map expected an array")
        }
        var mapped: [JSON] = []
        let intoSelf = try await into_self?.compute(
            context: context,
            runtime: runtime,
            route: route.appending(.key("into_self")),
            depth: depth + 1
        ).decode(Bool.self) ?? false
        for (index, value) in values.enumerated() {
            if let copy {
                let map = Keyword.Map(src: value, dst: intoSelf ? value : .object([:]), copy: copy)
                mapped.append(try await ComputeTaskLocal.$context.withValue(context.with(item: value)) {
                    try await map.compute(
                        context: ComputeTaskLocal.context,
                        runtime: runtime,
                        route: route.appending(.key("over")).appending(.index(index)),
                        depth: depth + 1
                    ) ?? .null
                })
            } else {
                mapped.append(value)
            }
        }
        let shouldFlatten = try await flattened?.compute(
            context: context,
            runtime: runtime,
            route: route.appending(.key("flattened")),
            depth: depth + 1
        ).decode(Bool.self) ?? false
        return try Self(over: .array(mapped), flattened: .bool(shouldFlatten)).compute()
    }
}
