extension JSON {
    func asList() -> [JSON] {
        switch self {
        case .null:
            return []
        case .array(let values):
            return values
        case .bool, .int, .double, .string, .object:
            return [self]
        }
    }

    var count: Int {
        switch self {
        case .null:
            return 0
        case .bool, .int, .double:
            return 1
        case .string(let value):
            return value.count
        case .array(let values):
            return values.count
        case .object(let object):
            return object.count
        }
    }

    var stableDescription: String {
        switch self {
        case .null:
            return "null"
        case .bool(let value):
            return "bool:\(value)"
        case .int(let value):
            return "int:\(value)"
        case .double(let value):
            return "double:\(value)"
        case .string(let value):
            return "string:\(value)"
        case .array(let values):
            return "[" + values.map(\.stableDescription).joined(separator: ",") + "]"
        case .object(let object):
            return "{" + object.keys.sorted().map { "\($0):\(object[$0]?.stableDescription ?? "nil")" }.joined(separator: ",") + "}"
        }
    }

    func value(at route: ComputeRoute) -> JSON? {
        var current = self
        for component in route.components {
            switch (component, current) {
            case (.key(let key), .object(let object)):
                guard let value = object[key] else { return nil }
                current = value
            case (.index(let index), .array(let array)):
                guard array.indices.contains(index) else { return nil }
                current = array[index]
            default:
                return nil
            }
        }
        return current
    }

    var isComputeInvocation: Bool {
        guard case .object(let object) = self else { return false }
        return Compute.Invocation(object: object) != nil
    }

    func conceptRoutes(
        functions: [String: any AnyReturnsKeyword],
        from route: ComputeRoute = .root
    ) -> [ComputeRoute] {
        switch self {
        case .object(let object):
            if let invocation = Compute.Invocation(object: object) {
                guard functions[invocation.keyword] != nil else {
                    let argumentRoute = route["{returns}", .key(invocation.keyword)]
                    return invocation.argument.conceptRoutes(functions: functions, from: argumentRoute)
                }
                return [route]
            }
            var routes: [ComputeRoute] = []
            for key in object.keys.sorted() {
                routes.append(contentsOf: object[key]?.conceptRoutes(
                    functions: functions,
                    from: route[.key(key)]
                ) ?? [])
            }
            return routes
        case .array(let values):
            var routes: [ComputeRoute] = []
            for (index, value) in values.enumerated() {
                routes.append(contentsOf: value.conceptRoutes(
                    functions: functions,
                    from: route[.index(index)]
                ))
            }
            return routes
        case .null, .bool, .int, .double, .string:
            return []
        }
    }

    mutating func set(_ value: JSON, at route: ComputeRoute) throws {
        try set(value, at: ArraySlice(route.components), path: route.path)
    }

    private mutating func set(
        _ value: JSON,
        at components: ArraySlice<ComputeRoute.Component>,
        path: [String]
    ) throws {
        guard let head = components.first else {
            self = value
            return
        }
        let tail = components.dropFirst()
        switch (head, self) {
        case (.key(let key), .object(var object)):
            var child = object[key] ?? .object([:])
            try child.set(value, at: tail, path: path)
            object[key] = child
            self = .object(object)
        case (.index(let index), .array(var array)):
            guard array.indices.contains(index) else {
                throw JSONError("Array index out of bounds", path: path)
            }
            var child = array[index]
            try child.set(value, at: tail, path: path)
            array[index] = child
            self = .array(array)
        default:
            throw JSONError("Cannot set value", path: path)
        }
    }

    func compute(
        frame: ComputeFrame
    ) async throws -> JSON {
        try await compute(context: frame.context, runtime: frame.runtime, route: frame.route, depth: frame.depth)
    }

    private func compute(
        context: Compute.Context,
        runtime: ComputeFunctionRuntime,
        route: ComputeRoute = .root,
        depth: Int
    ) async throws -> JSON {
        switch self {
        case .object(let object):
            if let invocation = Compute.Invocation(object: object) {
                guard depth < 20 else {
                    throw ComputeError.recursionLimitExceeded
                }

                let functionRoute = route["{returns}", .key(invocation.keyword)]
                do {
                    if let value = try await runtime.compute(
                        keyword: invocation.keyword,
                        argument: invocation.argument,
                        context: context,
                        route: functionRoute,
                        depth: depth
                    ) {
                        return value
                    }
                } catch {
                    if let fallback = invocation.fallback {
                        let fallbackRoute = route["default"]
                        let output = try await fallback.compute(
                            context: context,
                            runtime: runtime,
                            route: fallbackRoute,
                            depth: depth
                        )
                        await runtime.record(ComputeThought(
                            route: fallbackRoute,
                            depth: fallbackRoute.components.count,
                            keyword: "default",
                            kind: .defaultValue,
                            input: fallback,
                            output: output
                        ))
                        return output
                    }
                    throw error
                }
                if let fallback = invocation.fallback {
                    let fallbackRoute = route["default"]
                    let output = try await fallback.compute(
                        context: context,
                        runtime: runtime,
                        route: fallbackRoute,
                        depth: depth
                    )
                    await runtime.record(ComputeThought(
                        route: fallbackRoute,
                        depth: fallbackRoute.components.count,
                        keyword: "default",
                        kind: .defaultValue,
                        input: fallback,
                        output: output
                    ))
                    return output
                }
                return .null
            }

            var computed: [String: JSON] = [:]
            for key in object.keys.sorted() {
                computed[key] = try await object[key]?.compute(
                    context: context,
                    runtime: runtime,
                    route: route[.key(key)],
                    depth: depth
                )
            }
            return .object(computed)
        case .array(let values):
            var computed: [JSON] = []
            for (index, value) in values.enumerated() {
                computed.append(try await value.compute(
                    context: context,
                    runtime: runtime,
                    route: route[.index(index)],
                    depth: depth
                ))
            }
            return .array(computed)
        case .null, .bool, .int, .double, .string:
            return self
        }
    }

}
