import _JSON
import Algorithms

extension Compute.Keyword {
    public struct ArraySort: Codable, Equatable, Sendable {
        public static let name = "array_sort"

        @Computed public var array: [JSON]
        @Computed public var predicates: [Predicate]?

        public struct Predicate: Codable, Equatable, Sendable {
            public let key_path: [Compute.Route.Component]?
            public let order: Order

            public init(key_path: [Compute.Route.Component]? = nil, order: Order) {
                self.key_path = key_path
                self.order = order
            }
        }

        public enum Order: String, Codable, Sendable {
            case ascending
            case descending
        }
    }
}

extension Compute.Keyword.ArraySort: Compute.KeywordDefinition {
    public func compute(in frame: Compute.Frame) async throws -> JSON? {
        let values = try await $array.compute(in: frame)
        let predicates = try await $predicates.compute(in: frame) ?? []
        guard !predicates.isEmpty else {
            return .array(values)
        }
        let sorted = try values.indexed().sorted { lhs, rhs in
            for predicate in predicates {
                if let ordered = try predicate.areInIncreasingOrder(lhs.element, rhs.element) {
                    return ordered
                }
            }
            return lhs.index < rhs.index
        }.map(\.element)
        return .array(sorted)
    }
}

extension Compute.Keyword.ArraySort.Predicate {
    func areInIncreasingOrder(_ lhs: JSON, _ rhs: JSON) throws -> Bool? {
        let lhs = value(in: lhs)
        let rhs = value(in: rhs)
        guard lhs != rhs else {
            return nil
        }
        let ordered: Bool?
        switch (lhs.number, rhs.number) {
        case let (.some(left), .some(right)):
            ordered = order == .ascending ? left < right : left > right
        default:
            if let left = lhs.string, let right = rhs.string {
                ordered = order == .ascending ? left < right : left > right
            } else {
                ordered = nil
            }
        }
        return ordered
    }

    private func value(in json: JSON) -> JSON {
        guard let key_path else {
            return json
        }
        return json.value(at: key_path) ?? .null
    }
}

private extension JSON {
    var number: Double? {
        if let value = int {
            return Double(value)
        }
        if let value = double {
            return value
        }
        return nil
    }
}
