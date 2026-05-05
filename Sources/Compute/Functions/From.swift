public struct From: Codable, Equatable, Sendable {
    public let reference: JSON
    public let context: [String: JSON]?

    public init(reference: JSON, context: [String: JSON]? = nil) {
        self.reference = reference
        self.context = context
    }
}

public protocol ComputeReferences: Sendable {
    func value(for reference: JSON, context: [String: JSON]?) async throws -> JSON
}

extension From {
    public struct Function<References>: AnyReturnsKeyword where References: ComputeReferences {
        public let keyword = "from"
        private let references: References

        public init(references: References) {
            self.references = references
        }

        public func value(for input: JSON) async throws -> JSON {
            let from = try Self.parse(input)
            return try await references.value(for: from.reference, context: from.context)
        }

        private static func parse(_ input: JSON) throws -> From {
            guard case .object(let object) = input, let reference = object["reference"] else {
                return try JSON.decoded(From.self, from: input)
            }
            let context: [String: JSON]?
            if let value = object["context"] {
                guard case .object(let object) = value else {
                    return try JSON.decoded(From.self, from: input)
                }
                context = object
            } else {
                context = nil
            }
            return From(reference: reference, context: context)
        }
    }
}

public protocol AsyncComputeReferences: ComputeReferences {
    func values(for reference: JSON, context: [String: JSON]?) -> AsyncStream<Result<JSON, JSONError>>
}

extension From.Function: ReturnsKeyword where References: AsyncComputeReferences {
    public func values(for input: JSON) -> AsyncStream<Result<JSON, JSONError>> {
        do {
            let from = try Self.parse(input)
            return references.values(for: from.reference, context: from.context)
        } catch {
            return AsyncStream { continuation in
                continuation.yield(.failure(JSONError(error)))
                continuation.finish()
            }
        }
    }
}
