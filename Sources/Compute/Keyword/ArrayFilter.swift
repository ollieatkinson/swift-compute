extension Compute.Keyword {
    public struct ArrayFilter: Codable, Equatable, Sendable {
        @Computed public var array: [JSON]
        @Computed public var predicate: Bool
    }
}

extension Compute.Keyword.ArrayFilter: Compute.KeywordDefinition {
    public static let name = "array_filter"

    public func compute(in frame: Compute.Frame) async throws -> JSON? {
        let values: [JSON]
        do {
            values = try await $array.compute(in: frame)
        } catch {
            let error = JSONError(error)
            guard error.message.hasPrefix("Expected a [Any]") else {
                throw error
            }
            throw JSONError("array_filter expected an array", path: error.path)
        }
        var predicates: [Bool] = []
        for (index, value) in values.enumerated() {
            let keep = try await $predicate.compute(in: frame, item: value, appending: .index(index))
            predicates.append(keep)
        }
        guard predicates.count == values.count else {
            throw JSONError("array_filter predicate count did not match array count")
        }
        return .array(zip(values, predicates).filter(\.1).map(\.0))
    }
}
