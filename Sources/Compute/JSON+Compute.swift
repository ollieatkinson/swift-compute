import _JSON
import Algorithms

extension JSON {
    public static func returns(_ keyword: String, _ argument: JSON, default fallback: JSON? = nil) -> JSON {
        var object: Object = [
            "{returns}": .object([keyword: argument]),
        ]
        if let fallback {
            object["default"] = fallback
        }
        return .object(object)
    }

    var isComputeInvocation: Bool {
        guard let object else { return false }
        return Compute.Invocation(object: object) != nil
    }

    func conceptRoutes(
        functions: [String: any AnyReturnsKeyword],
        from route: Compute.Route = .root
    ) -> [Compute.Route] {
        if let object {
            if let invocation = Compute.Invocation(object: object) {
                guard functions[invocation.keyword] != nil else {
                    return invocation.argument.conceptRoutes(
                        functions: functions,
                        from: route["{returns}", .key(invocation.keyword)]
                    )
                }
                return [route]
            }
            return object.sortedEntries.flatMap { key, value in
                value.conceptRoutes(
                    functions: functions,
                    from: route[.key(key)]
                )
            }
        }

        if let values = array {
            return values.indexed().flatMap { index, value in
                value.conceptRoutes(
                    functions: functions,
                    from: route[.index(index)]
                )
            }
        }

        return []
    }

    mutating func set(_ value: JSON, at route: Compute.Route) throws {
        try set(value, at: ArraySlice(route.components), path: route.path)
    }

    private mutating func set(
        _ value: JSON,
        at components: ArraySlice<Compute.Route.Component>,
        path: [String]
    ) throws {
        guard let head = components.first else {
            self = value
            return
        }
        let tail = components.dropFirst()
        switch head {
        case .key(let key):
            guard var object else {
                throw JSONError("Cannot set value", path: path)
            }
            var child = object[key] ?? .object([:])
            try child.set(value, at: tail, path: path)
            object[key] = child
            self = .object(object)
        case .index(let index):
            guard var array else {
                throw JSONError("Cannot set value", path: path)
            }
            guard let index = array.resolvedIndex(index) else {
                throw JSONError("Array index out of bounds", path: path)
            }
            var child = array[index]
            try child.set(value, at: tail, path: path)
            array[index] = child
            self = .array(array)
        }
    }

    func compute(in frame: Compute.Frame) async throws -> JSON {
        try await compute(context: frame.context, runtime: frame.runtime, route: frame.route, depth: frame.depth)
    }

    private func compute(
        context: Compute.Context,
        runtime: Compute.FunctionRuntime,
        route: Compute.Route = .root,
        depth: Int
    ) async throws -> JSON {
        if let object {
            if let invocation = Compute.Invocation(object: object) {
                guard depth < 20 else {
                    throw Compute.Error.recursionLimitExceeded
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
                        return try await fallback.defaultValue(
                            context: context,
                            runtime: runtime,
                            route: route["default"],
                            depth: depth
                        )
                    }
                    throw error
                }
                if let fallback = invocation.fallback {
                    return try await fallback.defaultValue(
                        context: context,
                        runtime: runtime,
                        route: route["default"],
                        depth: depth
                    )
                }
                return .null
            }

            var computed: [String: JSON] = [:]
            for (key, value) in object.sortedEntries {
                computed[key] = try await value.compute(
                    context: context,
                    runtime: runtime,
                    route: route[.key(key)],
                    depth: depth
                )
            }
            return .object(computed)
        }

        if let values = array {
            var computed: [JSON] = []
            for (index, value) in values.indexed() {
                computed.append(try await value.compute(
                    context: context,
                    runtime: runtime,
                    route: route[.index(index)],
                    depth: depth
                ))
            }
            return .array(computed)
        }

        return self
    }

    private func defaultValue(
        context: Compute.Context,
        runtime: Compute.FunctionRuntime,
        route: Compute.Route,
        depth: Int
    ) async throws -> JSON {
        let output = try await compute(
            context: context,
            runtime: runtime,
            route: route,
            depth: depth
        )
        await runtime.record(Compute.Thought(
            route: route,
            depth: depth,
            keyword: "default",
            kind: .defaultValue,
            input: self,
            output: output
        ))
        return output
    }
}
