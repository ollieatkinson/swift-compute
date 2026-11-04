import _JSON

extension Compute {
    /// Per-evaluation observations within a returned program. The most specific
    /// completed value wins over an aggregate failure. Each source commits its
    /// outcomes in the existing graph signal, alongside its value or error.
    struct Projection: Sendable {
        private var targets: [Route: Route]
        private var outputs: [Route: (source: Route, result: Result<JSON, JSONError>)] = [:]

        init(observing: Set<Route>, document: JSON) {
            targets = Dictionary(uniqueKeysWithValues: observing.map {
                ($0, $0.resolvingIndices(in: document))
            })
        }

        func includes(_ route: Route) -> Bool {
            targets.values.contains { $0.isPrefix(of: route) || route.isPrefix(of: $0) }
        }

        func includesDescendants(of route: Route) -> Bool {
            targets.values.contains { route != $0 && route.isPrefix(of: $0) }
        }

        mutating func prepare(
            _ value: JSON,
            at route: Route
        ) -> [(Route, Result<JSON, JSONError>)] {
            normalize(value, at: route)
            var updates: [(Route, Result<JSON, JSONError>)] = []
            for (original, target) in targets where route.isPrefix(of: target) {
                guard let head = target.components.dropFirst(route.components.count).first
                else { continue }
                let missing: Bool
                switch head {
                case .key(let key): missing = value.object?[key] == nil
                case .index(let index): missing = value.array?.indices.contains(index) != true
                }
                if missing {
                    updates += store(
                        .failure(JSONError("Missing value", path: original.path)),
                        for: original,
                        source: route.appending(head)
                    )
                }
            }
            return updates
        }

        mutating func resolve(
            _ result: Result<JSON, JSONError>,
            at route: Route
        ) -> [(Route, Result<JSON, JSONError>)] {
            if case .success(let value) = result { normalize(value, at: route) }
            var updates: [(Route, Result<JSON, JSONError>)] = []
            for (original, target) in targets where route.isPrefix(of: target) {
                let selected = result.flatMap { value in
                    let suffix = Array(target.components.dropFirst(route.components.count))
                    return value.value(at: suffix).map(Result.success)
                        ?? .failure(JSONError("Missing value", path: original.path))
                }
                updates += store(selected, for: original, source: route)
            }
            return updates
        }

        func results(in route: Route) -> [Route: Result<JSON, JSONError>] {
            outputs.filter { route.isPrefix(of: $0.value.source) }.mapValues(\.result)
        }

        private mutating func normalize(_ value: JSON, at route: Route) {
            for (original, target) in targets where route.isPrefix(of: target) {
                let suffix = Route(Array(original.components.dropFirst(route.components.count)))
                targets[original] = route
                    .appending(contentsOf: suffix.resolvingIndices(in: value).components)
            }
        }

        private mutating func store(
            _ result: Result<JSON, JSONError>,
            for observed: Route,
            source: Route
        ) -> [(Route, Result<JSON, JSONError>)] {
            guard outputs[observed]
                .map({ $0.source.components.count <= source.components.count }) ?? true
            else { return [] }
            let previous = outputs[observed]?.result
            outputs[observed] = (source, result)
            return previous == result ? [] : [(observed, result)]
        }
    }
}
