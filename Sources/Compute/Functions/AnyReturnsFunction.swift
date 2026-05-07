public struct AnyReturnsFunction: ReturnsKeyword {
    public let name: String
    private let valueImplementation: @Sendable (JSON) async throws -> JSON
    private let valuesImplementation: @Sendable (JSON, ComputeFrame) -> AsyncStream<Result<JSON, JSONError>>

    public init(
        name: String,
        value: @escaping @Sendable (JSON) async throws -> JSON,
        values: @escaping @Sendable (JSON) -> AsyncStream<Result<JSON, JSONError>>
    ) {
        self.name = name
        self.valueImplementation = value
        self.valuesImplementation = { data, _ in values(data) }
    }

    public init(
        name: String,
        value: @escaping @Sendable (JSON) async throws -> JSON,
        subject: @escaping @Sendable (JSON, ComputeFrame) -> AsyncStream<Result<JSON, JSONError>>
    ) {
        self.name = name
        self.valueImplementation = value
        self.valuesImplementation = subject
    }

    public func compute(data input: JSON, frame: ComputeFrame) async throws -> JSON? {
        try await valueImplementation(input)
    }

    public func subject(data input: JSON, frame: ComputeFrame) -> AsyncStream<Result<JSON, JSONError>> {
        valuesImplementation(input, frame)
    }
}
