extension Compute.Keywords {
    public struct From: Codable, Equatable, Sendable {
        public static let name = "from"

        public let reference: JSON
        public let context: [String: JSON]?

        public init(reference: JSON, context: [String: JSON]? = nil) {
            self.reference = reference
            self.context = context
        }
    }
}

extension Compute {
    public protocol References: Sendable {
        func value(for reference: JSON, context: [String: JSON]?) async throws -> JSON
    }

    public protocol AsyncReferences: References {
        func values(for reference: JSON, context: [String: JSON]?) -> AsyncStream<Result<JSON, JSONError>>
    }
}

extension Compute.Keywords.From {
    public struct Function<References>: AnyReturnsKeyword where References: Compute.References {
        public let name = Compute.Keywords.From.name
        private let references: References

        public init(references: References) {
            self.references = references
        }

        public func compute(data input: JSON, frame: Compute.Frame) async throws -> JSON? {
            let from = try JSON.decoded(Compute.Keywords.From.self, from: input)
            return try await references.value(for: from.reference, context: from.context)
        }
    }
}

extension Compute.Keywords.From.Function: ReturnsKeyword where References: Compute.AsyncReferences {
    public func subject(data input: JSON, frame: Compute.Frame) -> AsyncStream<Result<JSON, JSONError>> {
        do {
            let from = try JSON.decoded(Compute.Keywords.From.self, from: input)
            return references.values(for: from.reference, context: from.context)
        } catch {
            let (stream, continuation) = AsyncStream.makeStream(of: Result<JSON, JSONError>.self)
            continuation.yield(.failure(JSONError(error)))
            continuation.finish()
            return stream
        }
    }
}
