extension Keyword {
    public struct Yes: Codable, Equatable, Sendable {
        public let `if`: JSON?
        public let unless: JSON?

        public init(if conditions: JSON? = nil, unless exceptions: JSON? = nil) {
            self.if = conditions
            self.unless = exceptions
        }
    }
}

extension Keyword.Yes: ComputeKeyword {
    public static let name = "yes"

    public func compute(in frame: ComputeFrame) async throws -> JSON? {
        let conditions = try await list(from: `if`, at: "if", frame: frame)
        let exceptions = try await list(from: unless, at: "unless", frame: frame)
        let satisfied = try conditions.allSatisfy { try $0.decode(Bool.self) }
        let blocked = try exceptions.contains { try $0.decode(Bool.self) }
        return .bool(satisfied && !blocked)
    }

    private func list(
        from value: JSON?,
        at route: ComputeRoute.Component,
        frame: ComputeFrame
    ) async throws -> [JSON] {
        guard let value else { return [] }
        return try await value.compute(frame: frame[route]).asList()
    }
}
