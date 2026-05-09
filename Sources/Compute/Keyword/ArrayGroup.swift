import _JSON
import Algorithms

extension Compute.Keyword {
    public struct ArrayGroup: Codable, Equatable, Sendable {
        public static let name = "array_group"

        @Computed public var array: [JSON]
        @Computed public var into: Into?
        public let by: By?

        public struct By: Codable, Equatable, Sendable {
            @Computed public var value: JSON
            @Computed public var order: Compute.Keyword.ArraySort.Order?
        }

        public struct Into: Codable, Equatable, Sendable {
            @Computed public var counts: [Int]
            @Computed public var overflow: Overflow?
            @Computed public var remainder: Remainder?
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

extension Compute.Keyword.ArrayGroup: Compute.KeywordDefinition {

    public func compute(in frame: Compute.Frame) async throws -> JSON? {
        let values = try await $array.compute(in: frame)
        let into = try await $into.compute(in: frame)
        switch try GroupingMode(into: into, by: by) {
        case .into(let into):
            let plan = try await IntoPlan(into, frame: frame)
            return .array(plan.groups(from: values).map(JSON.array))
        case .by(let by):
            return try await group(values, by: by, frame: frame)
        }
    }

    private func group(
        _ values: [JSON],
        by: By,
        frame: Compute.Frame
    ) async throws -> JSON {
        var keyedItems: [KeyedItem] = []
        for (index, value) in values.indexed() {
            let key = try await by.$value.compute(in: frame, item: value, appending: .index(index))
            keyedItems.append(KeyedItem(index: index, key: key, value: value))
        }
        let order = try await by.$order.compute(in: frame) ?? .ascending
        return .array(try ItemGroup.groups(from: keyedItems).elements(ordered: order).map(JSON.array))
    }
}

extension Compute.Keyword.ArrayGroup {
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

        init(_ into: Into, frame: Compute.Frame) async throws {
            let counts = try await into.$counts.compute(in: frame)
            let overflow = try await into.$overflow.compute(in: frame)
            let remainder = try await into.$remainder.compute(in: frame)
            self.counts = counts
            self.overflow = overflow ?? .trimmed
            self.remainder = remainder ?? .trimmed
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

private extension Array where Element == Compute.Keyword.ArrayGroup.ItemGroup {
    func elements(ordered order: Compute.Keyword.ArraySort.Order) throws -> [[JSON]] {
        let predicate = Compute.Keyword.ArraySort.Predicate(order: order)
        return try sorted { lhs, rhs in
            (try predicate.areInIncreasingOrder(lhs.key, rhs.key)) ?? (lhs.offset < rhs.offset)
        }.map(\.elements)
    }
}
