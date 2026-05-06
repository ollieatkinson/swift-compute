public struct AnyReturnsFunction: ReturnsKeyword {
    public let name: String
    private let valueImplementation: @Sendable (JSON) async throws -> JSON
    private let valuesImplementation: @Sendable (JSON) -> AsyncStream<Result<JSON, JSONError>>

    public init(
        name: String,
        value: @escaping @Sendable (JSON) async throws -> JSON,
        values: @escaping @Sendable (JSON) -> AsyncStream<Result<JSON, JSONError>>
    ) {
        self.name = name
        self.valueImplementation = value
        self.valuesImplementation = values
    }

    public func value(for input: JSON) async throws -> JSON {
        try await valueImplementation(input)
    }

    public func values(for input: JSON) -> AsyncStream<Result<JSON, JSONError>> {
        valuesImplementation(input)
    }
}
