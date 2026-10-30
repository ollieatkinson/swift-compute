import _JSON
extension Compute.Keyword {
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

extension Compute.Keyword.From {
    public struct Function<References>: AnyReturnsKeyword where References: Compute.References {
        public let name = Compute.Keyword.From.name
        private let references: References

        public init(references: References) {
            self.references = references
        }

        public func compute(data input: JSON, frame: Compute.Frame) async throws -> JSON? {
            let from = try JSON.decoded(Compute.Keyword.From.self, from: input)
            return try await references.value(for: from.reference, context: from.context)
        }
    }
}

extension Compute.Keyword.From.Function: Compute.ReturnsKeywordDefinition where References: Compute.AsyncReferences {
    public func subject(
        data input: JSON,
        frame: Compute.Frame,
        bufferingPolicy: Compute.ReturnsKeywordDefinition.BufferingPolicy
    ) -> AsyncStream<Result<JSON, JSONError>> {
        do {
            let from = try JSON.decoded(Compute.Keyword.From.self, from: input)
            return references.values(for: from.reference, context: from.context)
        } catch {
            let (stream, continuation) = AsyncStream.makeStream(
                of: Result<JSON, JSONError>.self,
                bufferingPolicy: bufferingPolicy
            )
            continuation.yield(.failure(JSONError(error)))
            continuation.finish()
            return stream
        }
    }
}

// Only reference providers have stable semantic request identity. Arbitrary
// streaming keywords may legitimately return different data at each depth.
protocol ReferenceKeyword: AnyReturnsKeyword {}
extension Compute.Keyword.From.Function: ReferenceKeyword {}

extension Compute.Keyword.From {
    var diagnosticName: String {
        let name = reference.string ?? reference.diagnosticJSON
        guard let context else { return name }
        return "\(name) \(JSON.object(context).diagnosticJSON)"
    }
}

private extension JSON {
    var diagnosticJSON: String {
        guard let data = try? data(options: [.fragmentsAllowed, .sortedKeys]) else {
            return String(describing: self)
        }
        return String(decoding: data, as: UTF8.self)
    }
}
