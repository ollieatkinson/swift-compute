import _JSON
extension Compute {
    public struct Frame: Sendable {
        public let context: Compute.Context
        let runtime: Compute.FunctionRuntime
        public let route: Compute.Route
        public let depth: Int

        init(
            context: Compute.Context,
            runtime: Compute.FunctionRuntime,
            route: Compute.Route,
            depth: Int
        ) {
            self.context = context
            self.runtime = runtime
            self.route = route
            self.depth = depth
        }

        public func compute(_ data: JSON, at route: Compute.Route? = nil) async throws -> JSON {
            try await data.compute(
                in: Frame(
                    context: context,
                    runtime: runtime,
                    route: route ?? self.route,
                    depth: depth
                )
            )
        }

        public subscript(route: Compute.Route.Component...) -> Frame {
            Frame(
                context: context,
                runtime: runtime,
                route: self.route.appending(contentsOf: route),
                depth: depth
            )
        }
    }
}
