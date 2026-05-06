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

    public func value(for input: JSON) async throws -> JSON {
        try valueImplementation(input)
    }
}
