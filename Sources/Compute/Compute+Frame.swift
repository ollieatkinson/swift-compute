import _JSON
extension Compute {
    public struct Frame: Sendable {
        public let context: Compute.Context
        let runtime: Compute.FunctionRuntime
        public let route: Compute.Route
        public let depth: Int
        // Immutable branch ancestry; sibling evaluations never share a mutable stack.
        let references: [(request: Compute.Keyword.From, context: Compute.Context)]
        let captures: [UInt64]
        // Logical output ownership is distinct from diagnostic/code routes.
        // Explicit routes and detached work keep their containing output scope.
        let output: Compute.Route?

        /// Effective reference defaults at this branch. Explicit `from` context
        /// and canonical provider bindings may narrow them further.
        public var scope: [String: JSON]? {
            context.referenceContext ?? references.last?.request.context
        }

        /// An explicit capture, such as `explain`, is active in this branch.
        /// An external evaluation stage can carry evidence back into that capture.
        public var isCapturing: Bool { !captures.isEmpty }

        /// An immutable branch scope. Siblings retain their original bindings,
        /// item, route, depth, reference ancestry and dependency owner.
        public func scoped(to bindings: [String: JSON]) -> Frame {
            var context = context
            context.referenceContext = (scope ?? [:]).merging(bindings) { _, narrower in narrower }
            return Frame(
                context: context,
                runtime: runtime,
                route: route,
                depth: depth,
                references: references,
                captures: captures,
                output: output
            )
        }

        init(
            context: Compute.Context,
            runtime: Compute.FunctionRuntime,
            route: Compute.Route,
            depth: Int,
            references: [(request: Compute.Keyword.From, context: Compute.Context)],
            captures: [UInt64] = [],
            output: Compute.Route? = nil
        ) {
            self.context = context
            self.runtime = runtime
            self.route = route
            self.depth = depth
            self.references = references
            self.captures = captures
            self.output = output
        }

        public func compute(_ data: JSON, at route: Compute.Route? = nil) async throws -> JSON {
            try await data.compute(
                in: Frame(
                    context: context,
                    runtime: runtime,
                    route: route ?? self.route,
                    depth: depth,
                    references: references,
                    captures: captures,
                    output: output
                )
            )
        }

        public subscript(route: Compute.Route.Component...) -> Frame {
            Frame(
                context: context,
                runtime: runtime,
                route: self.route.appending(contentsOf: route),
                depth: depth,
                references: references,
                captures: captures,
                output: output
            )
        }

        func recording(at output: Compute.Route) -> Frame {
            Frame(
                context: context,
                runtime: runtime,
                route: route,
                depth: depth,
                references: references,
                captures: captures,
                output: output
            )
        }

        /// Adds evidence from a custom keyword to this evaluation's trace.
        /// Recording does not evaluate the evidence or create a dependency.
        /// A recorded error is diagnostic evidence; throw to fail execution.
        /// Use this frame's route/depth when describing work in this frame.
        public func record(_ thought: Compute.Thought) async {
            await runtime.record(thought, captures: captures, output: output)
        }
    }
}
