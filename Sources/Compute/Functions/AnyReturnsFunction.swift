public struct AnyReturnsFunction: ReturnsKeyword {
    public let name: String
    private let valueImplementation: @Sendable (JSON) async throws -> JSON
    private let valuesImplementation: @Sendable (JSON, Compute.Frame) -> AsyncStream<Result<JSON, JSONError>>

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
        subject: @escaping @Sendable (JSON, Compute.Frame) -> AsyncStream<Result<JSON, JSONError>>
    ) {
        self.name = name
        self.valueImplementation = value
        self.valuesImplementation = subject
    }

    public func compute(data input: JSON, frame: Compute.Frame) async throws -> JSON? {
        try await valueImplementation(input)
    }

    public func subject(data input: JSON, frame: Compute.Frame) -> AsyncStream<Result<JSON, JSONError>> {
        valuesImplementation(input, frame)
    }
}
