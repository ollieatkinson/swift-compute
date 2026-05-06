extension Keyword {
    public struct ArraySort: Codable, Equatable, Sendable {
        public static let name = "array_sort"

        public let array: JSON
        public let predicates: [Predicate]?

        public init(array: JSON, predicates: [Predicate]? = nil) {
            self.array = array
            self.predicates = predicates
        }

        public struct Predicate: Codable, Equatable, Sendable {
            public let key_path: [ComputeRoute.Component]?
            public let order: Order

            public init(key_path: [ComputeRoute.Component]? = nil, order: Order) {
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

extension Keyword.ArraySort: ComputeKeyword {
    public func compute() throws -> JSON {
        guard case .array(let values) = array else {
            throw JSONError("array_sort expected an array")
        }
        guard let predicates, !predicates.isEmpty else {
            return .array(values)
        }
        let sorted = try values.enumerated().sorted { lhs, rhs in
            for predicate in predicates {
                if let ordered = try predicate.areInIncreasingOrder(lhs.element, rhs.element) {
                    return ordered
                }
            }
            return lhs.offset < rhs.offset
        }.map(\.element)
        return .array(sorted)
    }
}

extension Keyword.ArraySort.Predicate {
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
        return json.routeValue(at: ComputeRoute(key_path)) ?? .null
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
