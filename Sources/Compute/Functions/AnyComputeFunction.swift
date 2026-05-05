public struct AnyComputeFunction: AnyReturnsKeyword {
    public let keyword: String
    private let valueImplementation: @Sendable (JSON) throws -> JSON

    public init(
        keyword: String,
        value: @escaping @Sendable (JSON) throws -> JSON
    ) {
        self.keyword = keyword
        self.valueImplementation = value
    }

    public func value(for input: JSON) async throws -> JSON {
        try valueImplementation(input)
    }
}
