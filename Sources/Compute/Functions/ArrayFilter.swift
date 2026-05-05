public struct ArrayFilter: Codable, Equatable, Sendable {
    public let array: JSON
    public let predicate: JSON

    public init(array: JSON, predicate: JSON) {
        self.array = array
        self.predicate = predicate
    }
}

extension ArrayFilter: ComputeKeyword {
    public static let keyword = "array_filter"

    public func compute() throws -> JSON {
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
        var filtered: [JSON] = []
        for (value, keep) in zip(values, predicates) where keep {
            filtered.append(value)
        }
        return .array(filtered)
    }
}

extension ArrayFilter: CustomComputeKeyword {
    func compute(
        context: Compute.Context,
        runtime: ComputeFunctionRuntime,
        route: ComputeRoute,
        depth: Int
    ) async throws -> JSON? {
        let arrayRoute = route.appending(.key("array"))
        let predicateRoute = route.appending(.key("predicate"))
        let source = try await array.computeIfNeeded(
            context: context,
            runtime: runtime,
            route: arrayRoute,
            depth: depth
        )
        guard case .array(let values) = source else {
            throw JSONError("array_filter expected an array")
        }
        var filtered: [JSON] = []
        filtered.reserveCapacity(values.count)
        for (index, value) in values.enumerated() {
            let keep = try await ComputeTaskLocal.$context.withValue(context.with(item: value)) {
                try await predicate.compute(
                    context: ComputeTaskLocal.context,
                    runtime: runtime,
                    route: predicateRoute.appending(.index(index)),
                    depth: depth + 1
                )
            }
            if try keep.decode(Bool.self) {
                filtered.append(value)
            }
        }
        return .array(filtered)
    }
}
