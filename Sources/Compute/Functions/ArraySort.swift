import Algorithms

extension Compute.Keyword {
    public struct ArraySort: Codable, Equatable, Sendable {
        public static let name = "array_sort"

        @Computed public var array: JSON
        public let predicates: [Predicate]?

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
        let array = try await $array.compute(in: frame)
        guard case .array(let values) = array else {
            throw JSONError("array_sort expected an array")
        }
        guard let predicates, !predicates.isEmpty else {
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
            switch (lhs, rhs) {
            case let (.string(left), .string(right)):
                ordered = order == .ascending ? left < right : left > right
            default:
                ordered = nil
            }
        }
        return ordered
    }

    private func value(in json: JSON) -> JSON {
        guard let key_path else {
            return json
        }
        return json.value(at: Compute.Route(key_path)) ?? .null
    }
}

private extension JSON {
    var number: Double? {
        switch self {
        case .int(let value):
            return Double(value)
        case .double(let value):
            return value
        case .null, .bool, .string, .array, .object:
            return nil
        }
    }
}
