extension Compute.Keyword {
    public struct ArrayFilter: Codable, Equatable, Sendable {
        @Computed public var array: JSON
        @Computed public var predicate: JSON
    }
}

extension Compute.Keyword.ArrayFilter: Compute.KeywordDefinition {
    public static let name = "array_filter"

    public func compute(in frame: Compute.Frame) async throws -> JSON? {
        let source = try await $array.compute(in: frame)
        guard case .array(let values) = source else {
            throw JSONError("array_filter expected an array")
        }
        var predicates: [JSON] = []
        for (index, value) in values.enumerated() {
            let keep = try await $predicate.compute(in: frame, item: value, appending: .index(index))
            predicates.append(.bool(try keep.decode(Bool.self)))
        }
        return try Self.filtered(array: source, predicate: .array(predicates))
    }

    private static func filtered(array: JSON, predicate: JSON) throws -> JSON {
        guard case .array(let values) = array else {
            throw JSONError("array_filter expected an array")
        }
        let predicates: [Bool]
        switch predicate {
        case .array(let predicateValues):
            predicates = try predicateValues.map { try $0.decode(Bool.self) }
        default:
            let predicate = try predicate.decode(Bool.self)
            predicates = Array(repeating: predicate, count: values.count)
        }
        guard predicates.count == values.count else {
            throw JSONError("array_filter predicate count did not match array count")
        }
        return .array(zip(values, predicates).filter(\.1).map(\.0))
    }
}
