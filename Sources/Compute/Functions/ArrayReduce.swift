extension Keyword {
    public struct ArrayReduce: Codable, Equatable, Sendable {
        public static let name = "array_reduce"

        public let array: JSON
        public let initial: JSON
        public let next: JSON

        public init(array: JSON, initial: JSON, next: JSON) {
            self.array = array
            self.initial = initial
            self.next = next
        }
    }
}

extension Keyword.ArrayReduce: ComputeKeyword {
    public func compute() throws -> JSON {
        guard case .array = array else {
            throw JSONError("array_reduce expected an array")
        }
        return initial
    }
}

extension Keyword.ArrayReduce: CustomComputeKeyword {
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
            throw JSONError("array_reduce expected an array")
        }
        var accumulator = try await initial.compute(
            context: context,
            runtime: runtime,
            route: route.appending(.key("initial")),
            depth: depth
        )
        for (index, value) in values.enumerated() {
            let item: JSON = [
                "accumulator": accumulator,
                "index": .int(index),
                "item": value,
            ]
            accumulator = try await ComputeTaskLocal.$context.withValue(context.with(item: item)) {
                try await next.compute(
                    context: ComputeTaskLocal.context,
                    runtime: runtime,
                    route: route.appending(.key("next")).appending(.index(index)),
                    depth: depth
                )
            }
        }
        return accumulator
    }
}
