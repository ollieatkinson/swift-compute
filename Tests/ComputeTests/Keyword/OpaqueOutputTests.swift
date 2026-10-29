import Compute
import Testing

@Suite(.timeLimit(.minutes(1))) struct OpaqueOutputTests {
    @Test func a_custom_streaming_keyword_can_return_data_containing_expressions() async throws {
        let function = OpaqueSource()
        let runtime = Compute.Runtime(document: .returns(function.name, [:]), functions: [function])
        defer { await runtime.cancel() }
        var values = runtime.run().makeAsyncIterator()
        #expect(try await values.next()?.get() == payload)
    }

    @Test func a_keyword_definition_can_preserve_a_data_envelope() async throws {
        let runtime = Compute.Runtime(document: .returns(OpaqueDefinition.name, [:]), functions: [OpaqueDefinition.function])
        #expect(try await runtime.value() == payload)
    }
}

private let payload: JSON = ["body": ["{returns}": ["this": ["value": "Keep this expression as data"]]]]

private struct OpaqueSource: Compute.ReturnsKeywordDefinition, Compute.OpaqueOutputKeyword {
    let name = "opaque_source"
    func compute(data: JSON, frame: Compute.Frame) async throws -> JSON? { payload }
}

private struct OpaqueDefinition: Compute.OpaqueOutputKeywordDefinition {
    static let name = "opaque_definition"
    func compute(in frame: Compute.Frame) async throws -> JSON? { payload }
}
