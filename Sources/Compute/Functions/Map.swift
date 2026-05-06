extension Keyword {
    public struct Map: Codable, Equatable, Sendable {
        public let src: JSON
        public let dst: JSON?
        public let copy: [Copy]?

        public init(src: JSON, dst: JSON? = nil, copy: [Copy]? = nil) {
            self.src = src
            self.dst = dst
            self.copy = copy
        }

        public struct Copy: Codable, Equatable, Sendable {
            public let value: JSON
            public let to: [ComputeRoute.Component]

            public init(value: JSON, to: [String]) {
                self.init(value: value, to: to.map(ComputeRoute.Component.key))
            }

            public init(value: JSON, to: [ComputeRoute.Component]) {
                self.value = value
                self.to = to
            }
        }
    }
}

extension Keyword.Map: ComputeKeyword {
    public static let name = "map"

    public func compute() throws -> JSON {
        var destination = dst ?? src
        for copy in copy ?? [] {
            try destination.set(copy.value, at: ComputeRoute(copy.to))
        }
        return destination
    }
}

extension Keyword.Map: CustomComputeKeyword {
    func compute(
        context: Compute.Context,
        runtime: ComputeFunctionRuntime,
        route: ComputeRoute,
        depth: Int
    ) async throws -> JSON? {
        let source = try await src.compute(
            context: context,
            runtime: runtime,
            route: route.appending(.key("src")),
            depth: depth
        )
        var destination: JSON
        if let dst {
            destination = try await ComputeTaskLocal.$context.withValue(context.with(item: source)) {
                try await dst.compute(
                    context: ComputeTaskLocal.context,
                    runtime: runtime,
                    route: route.appending(.key("dst")),
                    depth: depth
                )
            }
        } else {
            destination = source
        }
        var copies: [Keyword.Map.Copy] = []
        for (index, copy) in (copy ?? []).enumerated() {
            let value = try await ComputeTaskLocal.$context.withValue(context.with(item: source)) {
                try await copy.value.compute(
                    context: ComputeTaskLocal.context,
                    runtime: runtime,
                    route: route.appending(.key("copy")).appending(.index(index)).appending(.key("value")),
                    depth: depth + 1
                )
            }
            copies.append(Keyword.Map.Copy(value: value, to: copy.to))
        }
        return try Self(src: source, dst: destination, copy: copies).compute()
    }
}
