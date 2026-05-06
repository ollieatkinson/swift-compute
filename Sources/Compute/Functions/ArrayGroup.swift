extension Keyword {
    public struct ArrayGroup: Codable, Equatable, Sendable {
        public static let name = "array_group"

        public let array: JSON
        public let into: Into?
        public let by: By?

        public init(array: JSON, into: Into? = nil, by: By? = nil) {
            self.array = array
            self.into = into
            self.by = by
        }

        public struct By: Codable, Equatable, Sendable {
            public let value: JSON
            public let order: JSON?

            public init(value: JSON, order: JSON? = nil) {
                self.value = value
                self.order = order
            }
        }

        public struct Into: Codable, Equatable, Sendable {
            public let counts: JSON
            public let overflow: JSON?
            public let remainder: JSON?

            public init(counts: JSON, overflow: JSON? = nil, remainder: JSON? = nil) {
                self.counts = counts
                self.overflow = overflow
                self.remainder = remainder
            }
        }

        public enum Overflow: String, Codable, Sendable {
            case trimmed
            case grouped
            case patterned
        }

        public enum Remainder: String, Codable, Sendable {
            case trimmed
            case grouped
        }
    }
}

extension Keyword.ArrayGroup: ComputeKeyword {
    public func compute() throws -> JSON {
        guard case .array(let values) = array else {
            throw JSONError("array_group expected an array")
        }
        switch (into, by) {
        case let (.some(into), .none):
            return try Self.group(values, into: into)
        case (.none, .some):
            throw JSONError("array_group by requires runtime item context")
        case (.none, .none), (.some, .some):
            throw JSONError("array_group expected exactly one of into or by")
        }
    }
}

extension Keyword.ArrayGroup: CustomComputeKeyword {
    func compute(
        context: Compute.Context,
        runtime: ComputeFunctionRuntime,
        route: ComputeRoute,
        depth: Int
    ) async throws -> JSON? {
        let source = try await array.compute(
            context: context,
            runtime: runtime,
            route: route.appending(.key("array")),
            depth: depth + 1
        )
        guard case .array(let values) = source else {
            throw JSONError("array_group expected an array")
        }
        switch (into, by) {
        case let (.some(into), .none):
            let counts = try await into.counts.compute(
                context: context,
                runtime: runtime,
                route: route.appending(.key("into")).appending(.key("counts")),
                depth: depth + 1
            )
            let overflow = try await into.overflow?.compute(
                context: context,
                runtime: runtime,
                route: route.appending(.key("into")).appending(.key("overflow")),
                depth: depth + 1
            )
            let remainder = try await into.remainder?.compute(
                context: context,
                runtime: runtime,
                route: route.appending(.key("into")).appending(.key("remainder")),
                depth: depth + 1
            )
            return try Self.group(
                values,
                into: Into(counts: counts, overflow: overflow, remainder: remainder)
            )
        case let (.none, .some(by)):
            return try await group(values, by: by, context: context, runtime: runtime, route: route, depth: depth)
        case (.none, .none), (.some, .some):
            throw JSONError("array_group expected exactly one of into or by")
        }
    }

    private func group(
        _ values: [JSON],
        by: By,
        context: Compute.Context,
        runtime: ComputeFunctionRuntime,
        route: ComputeRoute,
        depth: Int
    ) async throws -> JSON {
        var groups: [(key: JSON, elements: [JSON], offset: Int)] = []
        for (index, value) in values.enumerated() {
            let key = try await ComputeTaskLocal.$context.withValue(context.with(item: value)) {
                try await by.value.compute(
                    context: ComputeTaskLocal.context,
                    runtime: runtime,
                    route: route.appending(.key("by")).appending(.key("value")).appending(.index(index)),
                    depth: depth + 1
                )
            }
            if let existing = groups.firstIndex(where: { $0.key == key }) {
                groups[existing].elements.append(value)
            } else {
                groups.append((key: key, elements: [value], offset: groups.count))
            }
        }
        let order = try await by.order?.compute(
            context: context,
            runtime: runtime,
            route: route.appending(.key("by")).appending(.key("order")),
            depth: depth + 1
        ).decode(Keyword.ArraySort.Order.self) ?? .ascending
        let predicate = Keyword.ArraySort.Predicate(order: order)
        let sorted = try groups.sorted { lhs, rhs in
            (try predicate.areInIncreasingOrder(lhs.key, rhs.key)) ?? (lhs.offset < rhs.offset)
        }
        return .array(sorted.map { JSON.array($0.elements) })
    }
}

extension Keyword.ArrayGroup {
    private static func group(_ values: [JSON], into: Into) throws -> JSON {
        let counts = try into.counts.decode([Int].self)
        guard !counts.isEmpty else {
            return .array([])
        }
        guard counts.allSatisfy({ $0 > 0 }) else {
            throw JSONError("array_group counts must be greater than zero")
        }
        let overflow = try into.overflow?.decode(Overflow.self) ?? .trimmed
        let remainder = try into.remainder?.decode(Remainder.self) ?? .trimmed
        var groups: [[JSON]] = []
        var index = 0

        for count in counts {
            guard appendGroup(from: values, index: &index, count: count, remainder: remainder, to: &groups) else {
                return .array(groups.map(JSON.array))
            }
        }

        switch overflow {
        case .trimmed:
            break
        case .grouped:
            if index < values.count {
                groups.append(Array(values[index..<values.count]))
            }
        case .patterned:
            while index < values.count {
                var appendedInPattern = false
                for count in counts {
                    let previousIndex = index
                    if appendGroup(from: values, index: &index, count: count, remainder: remainder, to: &groups) {
                        appendedInPattern = true
                    }
                    if previousIndex == index {
                        return .array(groups.map(JSON.array))
                    }
                    guard index < values.count else {
                        break
                    }
                }
                guard appendedInPattern else {
                    break
                }
            }
        }
        return .array(groups.map(JSON.array))
    }

    private static func appendGroup(
        from values: [JSON],
        index: inout Int,
        count: Int,
        remainder: Remainder,
        to groups: inout [[JSON]]
    ) -> Bool {
        let end = index + count
        guard end <= values.count else {
            if remainder == .grouped, index < values.count {
                groups.append(Array(values[index..<values.count]))
                index = values.count
                return true
            }
            return false
        }
        groups.append(Array(values[index..<end]))
        index = end
        return true
    }
}
