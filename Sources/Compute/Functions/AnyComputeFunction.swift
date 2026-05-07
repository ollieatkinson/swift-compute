public struct AnyComputeFunction: AnyReturnsKeyword {
    public let name: String
    private let valueImplementation: @Sendable (JSON) throws -> JSON

    public init(
        name: String,
        value: @escaping @Sendable (JSON) throws -> JSON
    ) {
        self.name = name
        self.valueImplementation = value
    }

    public func compute(data input: JSON, frame: Compute.Frame) async throws -> JSON? {
        let input = try await frame.compute(input)
        return try valueImplementation(input)
    }
}
