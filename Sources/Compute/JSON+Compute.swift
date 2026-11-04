import _JSON
import Algorithms

extension JSON {
    public static func returns(
        _ keyword: String,
        _ data: JSON,
        default fallback: JSON? = nil
    ) -> JSON {
        var object: Object = [
            "{returns}": .object([keyword: data]),
        ]
        if let fallback {
            object["default"] = fallback
        }
        return .object(object)
    }

    func conceptRoutes(from route: Compute.Route = .root) -> [Compute.Route] {
        if let object {
            // Syntax identifies an invocation; execution validates capability.
            // Opaque output and literal boundaries remain the evaluator's job.
            if Compute.Invocation(object: object) != nil { return [route] }
            return object.sortedEntries.flatMap { key, value in
                value.conceptRoutes(
                    from: route[.key(key)]
                )
            }
        }

        if let values = array {
            return values.indexed().flatMap { index, value in
                value.conceptRoutes(
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

    func compute(
        in frame: Compute.Frame,
        projecting output: Compute.Route? = nil
    ) async throws -> JSON {
        guard let output else { return try await evaluate(in: frame, projecting: nil) }
        do {
            // Only containers with a requested descendant need independent
            // child progress. Other branches retain ordinary atomic evaluation.
            let descendants = await frame.runtime.projectsDescendants(of: output)
            let value = try await evaluate(in: frame, projecting: descendants ? output : nil)
            await frame.runtime.project(.success(value), at: output)
            return value
        } catch {
            if !(error is CancellationError) {
                await frame.runtime.project(.failure(JSONError(error)), at: output)
            }
            throw error
        }
    }

    private func evaluate(
        in frame: Compute.Frame,
        projecting output: Compute.Route?
    ) async throws -> JSON {
        try Task.checkCancellation()
        if let object {
            if let invocation = Compute.Invocation(object: object) {
                guard frame.depth < 20 else { throw Compute.Error.recursionLimitExceeded }
                do {
                    if let value = try await frame.runtime.compute(
                        keyword: invocation.keyword,
                        data: invocation.data,
                        context: frame.context,
                        route: frame.route["{returns}", .key(invocation.keyword)],
                        depth: frame.depth,
                        references: frame.references,
                        captures: frame.captures,
                        projecting: invocation.default == nil ? output : nil
                    ) { return value }
                } catch {
                    if let fallback = invocation.default {
                        return try await fallback.defaultValue(in: frame["default"])
                    }
                    throw error
                }
                if let fallback = invocation.default {
                    return try await fallback.defaultValue(in: frame["default"])
                }
                return .null
            }
            let entries = object.sortedEntries
            if let output {
                await frame.runtime.prepareProjection(self, at: output)
                let values = try await Self.compute(
                    entries.map { (.key($0.key), $0.value) },
                    in: frame,
                    projecting: output
                )
                return .object(Dictionary(uniqueKeysWithValues: values.map { (
                    entries[$0.key].key,
                    $0.value
                ) }))
            }
            var computed: [String: JSON] = [:]
            for (key, value) in entries {
                computed[key] = try await value.compute(in: frame[.key(key)])
            }
            return .object(computed)
        }
        if let values = array {
            if let output {
                await frame.runtime.prepareProjection(self, at: output)
                let results = try await Self.compute(
                    values.enumerated().map { (.index($0.offset), $0.element) },
                    in: frame,
                    projecting: output
                )
                var computed = values
                for (index, value) in results { computed[index] = value }
                return .array(computed)
            }
            var computed: [JSON] = []
            for (index, value) in values
                .indexed() { computed.append(try await value.compute(in: frame[.index(index)])) }
            return .array(computed)
        }
        return self
    }

    private static func compute(
        _ children: [(Compute.Route.Component, JSON)],
        in frame: Compute.Frame,
        projecting output: Compute.Route
    ) async throws -> [Int: JSON] {
        try await withThrowingTaskGroup(of: (Int, Result<JSON, JSONError>).self) { group in
            for (index, entry) in children.enumerated() {
                let selected = output.appending(entry.0)
                guard await frame.runtime.includesProjection(selected) else { continue }
                group.addTask {
                    do {
                        return (
                            index,
                            .success(try await entry.1.compute(
                                in: frame[entry.0],
                                projecting: selected
                            ))
                        )
                    } catch {
                        try Task.checkCancellation()
                        return (index, .failure(JSONError(error)))
                    }
                }
            }
            var values: [Int: JSON] = [:]
            var errors: [Int: JSONError] = [:]
            for try await (index, result) in group {
                switch result {
                case .success(let value): values[index] = value
                case .failure(let error): errors[index] = error
                }
            }
            if let index = errors.keys.min(), let error = errors[index] { throw error }
            return values
        }
    }

    private func defaultValue(in frame: Compute.Frame) async throws -> JSON {
        let output = try await compute(in: frame)
        await frame.record(Compute.Thought(
            route: frame.route,
            depth: frame.depth,
            keyword: "default",
            kind: .defaultValue,
            input: self,
            output: output
        ))
        return output
    }
}
