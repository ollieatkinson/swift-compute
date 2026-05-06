extension Keyword {
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

public protocol ComputeReferences: Sendable {
    func value(for reference: JSON, context: [String: JSON]?) async throws -> JSON
}

extension Keyword.From {
    public struct Function<References>: AnyReturnsKeyword where References: ComputeReferences {
        public let name = Keyword.From.name
        private let references: References

        public init(references: References) {
            self.references = references
        }

        public func value(for input: JSON) async throws -> JSON {
            let from = try JSON.decoded(Keyword.From.self, from: input)
            return try await references.value(for: from.reference, context: from.context)
        }
    }
}

public protocol AsyncComputeReferences: ComputeReferences {
    func values(for reference: JSON, context: [String: JSON]?) -> AsyncStream<Result<JSON, JSONError>>
}

extension Keyword.From.Function: ReturnsKeyword where References: AsyncComputeReferences {
    public func values(for input: JSON) -> AsyncStream<Result<JSON, JSONError>> {
        do {
            let from = try JSON.decoded(Keyword.From.self, from: input)
            return references.values(for: from.reference, context: from.context)
        } catch {
            return AsyncStream { continuation in
                continuation.yield(.failure(JSONError(error)))
                continuation.finish()
            }
        }
    }
}
