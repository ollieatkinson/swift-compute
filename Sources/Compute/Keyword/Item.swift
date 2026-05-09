import _JSON
extension Compute.Keyword {
    public struct Item: Equatable, Sendable {
        public let path: [Compute.Route.Component]

        public init(_ path: [Compute.Route.Component]) {
            self.path = path
        }
    }
}

extension Compute.Keyword.Item: Codable {
    public init(from decoder: Decoder) throws {
        self.init(try [Compute.Route.Component](from: decoder))
    }

    public func encode(to encoder: Encoder) throws {
        try path.encode(to: encoder)
    }
}

extension Compute.Keyword.Item: Compute.KeywordDefinition {
    public static let name = "item"

    public func compute(in frame: Compute.Frame) async throws -> JSON? {
        let source = frame.context.item ?? .null
        return source.value(at: path) ?? .null
    }
}
