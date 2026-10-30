import _JSON
extension Compute {
    public struct Frame: Sendable {
        public let context: Compute.Context
        let runtime: Compute.FunctionRuntime
        public let route: Compute.Route
        public let depth: Int
        // Immutable branch ancestry; sibling evaluations never share a mutable stack.
        let references: [(request: Compute.Keyword.From, context: Compute.Context)]

        init(
            context: Compute.Context,
            runtime: Compute.FunctionRuntime,
            route: Compute.Route,
            depth: Int,
            references: [(request: Compute.Keyword.From, context: Compute.Context)]
        ) {
            self.context = context
            self.runtime = runtime
            self.route = route
            self.depth = depth
            self.references = references
        }

        public func compute(_ data: JSON, at route: Compute.Route? = nil) async throws -> JSON {
            try await data.compute(
                in: Frame(
                    context: context,
                    runtime: runtime,
                    route: route ?? self.route,
                    depth: depth,
                    references: references
                )
            )
        }

        public subscript(route: Compute.Route.Component...) -> Frame {
            Frame(
                context: context,
                runtime: runtime,
                route: self.route.appending(contentsOf: route),
                depth: depth,
                references: references
            )
        }

        /// Adds evidence from a custom keyword to this evaluation's trace.
        /// Recording does not evaluate the evidence or create a dependency.
        /// Use this frame's route/depth when describing work in this frame.
        public func record(_ thought: Compute.Thought) async {
            await runtime.record(thought)
        }
    }
}
