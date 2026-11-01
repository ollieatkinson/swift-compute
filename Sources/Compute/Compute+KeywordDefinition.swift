import _JSON
public protocol AnyReturnsKeyword: Sendable {
    var name: String { get }

    func compute(data: JSON, frame: Compute.Frame) async throws -> JSON?
}

extension Compute {
    public protocol KeywordDefinition: Codable, Equatable, Sendable {
        static var name: String { get }
        func compute(in frame: Compute.Frame) async throws -> JSON?
    }

    /// Opts a keyword definition out of recursively evaluating its returned data.
    public protocol OpaqueOutputKeywordDefinition: KeywordDefinition {}
    /// Opts a custom function out of recursively evaluating its returned data.
    public protocol OpaqueOutputKeyword: AnyReturnsKeyword {}
}

extension Compute.Keyword {
    public struct Function<K: Compute.KeywordDefinition>: AnyReturnsKeyword {
        public var name: String {
            K.name
        }

        public init() {}

        public func compute(data: JSON, frame: Compute.Frame) async throws -> JSON? {
            try await JSON.decoded(K.self, from: data).compute(in: frame)
        }
    }
}

extension Compute.Keyword.Function: Compute.OpaqueOutputKeyword where K: Compute.OpaqueOutputKeywordDefinition {}

extension Compute.KeywordDefinition {
    public static var function: Compute.Keyword.Function<Self> {
        Compute.Keyword.Function()
    }
}

extension Compute {
    public protocol ReturnsKeywordDefinition: AnyReturnsKeyword {
        typealias BufferingPolicy = AsyncStream<Result<JSON, JSONError>>.Continuation.BufferingPolicy
        /// Pure request normalization, after input evaluation and before live
        /// dependency sharing. Include effective scope in the returned identity.
        func request(data: JSON, frame: Compute.Frame) async throws -> JSON
        func subject(data: JSON, frame: Compute.Frame, bufferingPolicy: BufferingPolicy) -> AsyncStream<Result<JSON, JSONError>>
    }
}

extension Compute.ReturnsKeywordDefinition {
    public func request(data: JSON, frame: Compute.Frame) async throws -> JSON { data }

    public func subject(data: JSON, frame: Compute.Frame, bufferingPolicy: BufferingPolicy) -> AsyncStream<Result<JSON, JSONError>> {
        let (stream, continuation) = AsyncStream.makeStream(
            of: Result<JSON, JSONError>.self,
            bufferingPolicy: bufferingPolicy
        )
        let task = Task { @concurrent in
            do {
                let dependency = Compute.Dependency(keyword: name, data: data, depth: frame.depth)
                let initial = await frame.runtime.result(for: dependency)
                try Task.checkCancellation()
                if let initial {
                    continuation.yield(initial)
                } else if let value = try await compute(data: data, frame: frame) {
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
