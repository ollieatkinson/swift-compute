import Algorithms

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
        switch try GroupingMode(into: into, by: by) {
        case .into(let into):
            return .array(try IntoPlan(into).groups(from: values).map(JSON.array))
        case .by:
            throw JSONError("array_group by requires runtime item context")
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
            depth: depth
        )
        guard case .array(let values) = source else {
            throw JSONError("array_group expected an array")
        }
        switch try GroupingMode(into: into, by: by) {
        case .into(let into):
            let plan = try await IntoPlan(
                into,
                context: context,
                runtime: runtime,
                route: route,
                depth: depth
            )
            return .array(plan.groups(from: values).map(JSON.array))
        case .by(let by):
            return try await group(values, by: by, context: context, runtime: runtime, route: route, depth: depth)
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
        var keyedItems: [KeyedItem] = []
        for (index, value) in values.enumerated() {
            let key = try await ComputeTaskLocal.$context.withValue(context.with(item: value)) {
                try await by.value.compute(
                    context: ComputeTaskLocal.context,
                    runtime: runtime,
                    route: route.appending(.key("by")).appending(.key("value")).appending(.index(index)),
                    depth: depth
                )
            }
            keyedItems.append(KeyedItem(index: index, key: key, value: value))
        }
        let orderValue = try await by.order?.compute(
            context: context,
            runtime: runtime,
            route: route.appending(.key("by")).appending(.key("order")),
            depth: depth
        )
        let order = try orderValue?.decode(Keyword.ArraySort.Order.self) ?? .ascending
        return .array(try ItemGroup.groups(from: keyedItems).elements(ordered: order).map(JSON.array))
    }
}

extension Keyword.ArrayGroup {
    fileprivate enum GroupingMode {
        case into(Into)
        case by(By)

        init(into: Into?, by: By?) throws {
            switch (into, by) {
            case let (.some(into), .none):
                self = .into(into)
            case let (.none, .some(by)):
                self = .by(by)
            case (.none, .none), (.some, .some):
                throw JSONError("array_group expected exactly one of into or by")
            }
        }
    }

    fileprivate struct IntoPlan {
        let counts: [Int]
        let overflow: Overflow
        let remainder: Remainder

        init(_ into: Into) throws {
            self.counts = try into.counts.decode([Int].self)
            self.overflow = try into.overflow?.decode(Overflow.self) ?? .trimmed
            self.remainder = try into.remainder?.decode(Remainder.self) ?? .trimmed
            try validate()
        }

        init(
            _ into: Into,
            context: Compute.Context,
            runtime: ComputeFunctionRuntime,
            route: ComputeRoute,
            depth: Int
        ) async throws {
            let counts = try await into.counts.compute(
                context: context,
                runtime: runtime,
                route: route.appending(.key("into")).appending(.key("counts")),
                depth: depth
            )
            let overflow = try await into.overflow?.compute(
                context: context,
                runtime: runtime,
                route: route.appending(.key("into")).appending(.key("overflow")),
                depth: depth
            )
            let remainder = try await into.remainder?.compute(
                context: context,
                runtime: runtime,
                route: route.appending(.key("into")).appending(.key("remainder")),
                depth: depth
            )
            self.counts = try counts.decode([Int].self)
            self.overflow = try overflow?.decode(Overflow.self) ?? .trimmed
            self.remainder = try remainder?.decode(Remainder.self) ?? .trimmed
            try validate()
        }

        func groups(from values: [JSON]) -> [[JSON]] {
            guard !counts.isEmpty else {
                return []
            }
            var cursor = GroupCursor(values)
            let firstPass = consume(counts, from: &cursor)
            var result = firstPass.groups
            guard firstPass.completed, cursor.hasRemaining else {
                return result
            }
            switch overflow {
            case .trimmed:
                return result
            case .grouped:
                if let remaining = cursor.takeRemaining() {
                    result.append(remaining)
                }
                return result
            case .patterned:
                result += consume(counts.cycled(), from: &cursor).groups
                return result
            }
        }

        private func validate() throws {
            guard counts.allSatisfy({ $0 > 0 }) else {
                throw JSONError("array_group counts must be greater than zero")
            }
        }

        private func consume<Counts: Sequence>(
            _ counts: Counts,
            from cursor: inout GroupCursor
        ) -> (groups: [[JSON]], completed: Bool) where Counts.Element == Int {
            var groups: [[JSON]] = []
            for count in counts {
                guard let group = cursor.take(count, remainder: remainder) else {
                    return (groups, false)
                }
                groups.append(group)
                guard cursor.hasRemaining else {
                    return (groups, true)
                }
            }
            return (groups, true)
        }
    }

    fileprivate struct GroupCursor {
        let values: [JSON]
        var index = 0

        init(_ values: [JSON]) {
            self.values = values
        }

        var hasRemaining: Bool {
            index < values.count
        }

        mutating func take(_ count: Int, remainder: Remainder) -> [JSON]? {
            let end = index + count
            guard end <= values.count else {
                guard remainder == .grouped else {
                    return nil
                }
                return takeRemaining()
            }
            let group = Array(values[index..<end])
            index = end
            return group
        }

        mutating func takeRemaining() -> [JSON]? {
            guard hasRemaining else {
                return nil
            }
            let group = Array(values[index..<values.count])
            index = values.count
            return group
        }
    }

    fileprivate struct KeyedItem {
        let index: Int
        let key: JSON
        let value: JSON
    }

    fileprivate struct ItemGroup {
        let key: JSON
        let elements: [JSON]
        let offset: Int

        static func groups(from items: [KeyedItem]) -> [ItemGroup] {
            items.grouped { $0.key }.map { key, items in
                ItemGroup(key: key, elements: items.map(\.value), offset: items[0].index)
            }
        }
    }
}

private extension Array where Element == Keyword.ArrayGroup.ItemGroup {
    func elements(ordered order: Keyword.ArraySort.Order) throws -> [[JSON]] {
        let predicate = Keyword.ArraySort.Predicate(order: order)
        return try sorted { lhs, rhs in
            (try predicate.areInIncreasingOrder(lhs.key, rhs.key)) ?? (lhs.offset < rhs.offset)
        }.map(\.elements)
    }
}
