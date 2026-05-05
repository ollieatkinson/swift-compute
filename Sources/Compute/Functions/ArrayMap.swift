public struct ArrayMap: Codable, Equatable, Sendable {
    public let over: JSON
    public let copy: [Map.Copy]?
    public let into_self: JSON?
    public let flattened: JSON?

    public init(over: JSON, copy: [Map.Copy]? = nil, into_self: JSON? = nil, flattened: JSON? = nil) {
        self.over = over
        self.copy = copy
        self.into_self = into_self
        self.flattened = flattened
    }
}

extension ArrayMap: ComputeKeyword {
    public static let keyword = "array_map"

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

extension ArrayMap: CustomComputeKeyword {
    func compute(
        context: Compute.Context,
        runtime: ComputeFunctionRuntime,
        route: ComputeRoute,
        depth: Int
    ) async throws -> JSON? {
        let source = try await over.computeIfNeeded(
            context: context,
            runtime: runtime,
            route: route.appending(.key("over")),
            depth: depth
        )
        guard case .array(let values) = source else {
            throw JSONError("array_map expected an array")
        }
        var mapped: [JSON] = []
        mapped.reserveCapacity(values.count)
        let intoSelf = try await into_self?.compute(
            context: context,
            runtime: runtime,
            route: route.appending(.key("into_self")),
            depth: depth + 1
        ).decode(Bool.self) ?? false
        for (index, value) in values.enumerated() {
            if let copy {
                let itemRoute = route.appending(.key("over"), .index(index))
                let output = try await ComputeTaskLocal.$context.withValue(context.with(item: value)) {
                    var destination = intoSelf ? value : JSON.object([:])
                    for (copyIndex, copy) in copy.enumerated() {
                        let copyRoute = itemRoute.appending(.key("copy"), .index(copyIndex)).appending(.key("value"))
                        let copied = try await copy.value.compute(
                            context: ComputeTaskLocal.context,
                            runtime: runtime,
                            route: copyRoute,
                            depth: depth + 1
                        )
                        try destination.set(copied, at: ComputeRoute(copy.to))
                    }
                    return destination
                }
                mapped.append(output)
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
        return try ArrayMap(over: .array(mapped), flattened: .bool(shouldFlatten)).compute()
    }
}
