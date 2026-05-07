public struct ComputeFrame: Sendable {
    public let context: Compute.Context
    let runtime: ComputeFunctionRuntime
    public let route: ComputeRoute
    public let depth: Int

    public func compute(_ data: JSON, at route: ComputeRoute? = nil) async throws -> JSON {
        try await data.compute(frame: ComputeFrame(
            context: context,
            runtime: runtime,
            route: route ?? self.route,
            depth: depth
        ))
    }

    func incrementDepth() -> ComputeFrame {
        ComputeFrame(context: context, runtime: runtime, route: route, depth: depth + 1)
    }

    public subscript(route: ComputeRoute.Component...) -> ComputeFrame {
        ComputeFrame(
            context: context,
            runtime: runtime,
            route: self.route.appending(contentsOf: route),
            depth: depth
        )
    }

    public subscript(item item: JSON, _ route: ComputeRoute.Component...) -> ComputeFrame {
        ComputeFrame(
            context: context.with(item: item),
            runtime: runtime,
            route: self.route.appending(contentsOf: route),
            depth: depth + 1
        )
    }
}

public protocol AnyReturnsKeyword: Sendable {
    var name: String { get }

    func compute(data: JSON, frame: ComputeFrame) async throws -> JSON?
}

public protocol ComputeKeyword: Codable, Equatable, Sendable {
    static var name: String { get }
    func compute(in frame: ComputeFrame) async throws -> JSON?
}

public struct ComputeKeywordFunction<K: ComputeKeyword>: AnyReturnsKeyword {
    public var name: String {
        K.name
    }

    public init() {}

    public func compute(data: JSON, frame: ComputeFrame) async throws -> JSON? {
        try await JSON.decoded(K.self, from: data).compute(in: frame)
    }
}

public extension ComputeKeyword {
    static var function: ComputeKeywordFunction<Self> {
        ComputeKeywordFunction()
    }
}

public protocol ReturnsKeyword: AnyReturnsKeyword {
    func subject(data: JSON, frame: ComputeFrame) -> AsyncStream<Result<JSON, JSONError>>
}

extension ReturnsKeyword {
    public func subject(data: JSON, frame: ComputeFrame) -> AsyncStream<Result<JSON, JSONError>> {
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
