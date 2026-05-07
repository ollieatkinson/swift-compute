extension Compute {
    public struct Frame: Sendable {
        public let context: Compute.Context
        let runtime: Compute.FunctionRuntime
        public let route: Compute.Route
        public let depth: Int

        init(
            context: Compute.Context, runtime: Compute.FunctionRuntime, route: Compute.Route, depth: Int
        ) {
            self.context = context
            self.runtime = runtime
            self.route = route
            self.depth = depth
        }

        public func compute(_ data: JSON, at route: Compute.Route? = nil) async throws -> JSON {
            try await data.compute(
                frame: Frame(
                    context: context,
                    runtime: runtime,
                    route: route ?? self.route,
                    depth: depth
                ))
        }

        func incrementDepth() -> Frame {
            Frame(context: context, runtime: runtime, route: route, depth: depth + 1)
        }

        public subscript(route: Compute.Route.Component...) -> Frame {
            Frame(
                context: context,
                runtime: runtime,
                route: self.route.appending(contentsOf: route),
                depth: depth
            )
        }

        public subscript(item item: JSON, _ route: Compute.Route.Component...) -> Frame {
            Frame(
                context: context.with(item: item),
                runtime: runtime,
                route: self.route.appending(contentsOf: route),
                depth: depth + 1
            )
        }
    }
}

public protocol AnyReturnsKeyword: Sendable {
    var name: String { get }

    func compute(data: JSON, frame: Compute.Frame) async throws -> JSON?
}

extension Compute {
    public protocol Keyword: Codable, Equatable, Sendable {
        static var name: String { get }
        func compute(in frame: Compute.Frame) async throws -> JSON?
    }

    public struct KeywordFunction<K: Keyword>: AnyReturnsKeyword {
        public var name: String {
            K.name
        }

        public init() {}

        public func compute(data: JSON, frame: Compute.Frame) async throws -> JSON? {
            try await JSON.decoded(K.self, from: data).compute(in: frame)
        }
    }
}

extension Compute.Keyword {
    public static var function: Compute.KeywordFunction<Self> {
        Compute.KeywordFunction()
    }
}

public protocol ReturnsKeyword: AnyReturnsKeyword {
    func subject(data: JSON, frame: Compute.Frame) -> AsyncStream<Result<JSON, JSONError>>
}

extension ReturnsKeyword {
    public func subject(data: JSON, frame: Compute.Frame) -> AsyncStream<Result<JSON, JSONError>> {
        let (stream, continuation) = AsyncStream.makeStream(
            of: Result<JSON, JSONError>.self,
            bufferingPolicy: .unbounded
        )
        let task = Task {
            do {
                if let value = try await compute(data: data, frame: frame) {
                    continuation.yield(.success(value))
                }
            } catch {
                continuation.yield(.failure(JSONError(error)))
            }
            continuation.finish()
        }
        continuation.onTermination = { @Sendable _ in task.cancel() }
        return stream
    }
}
