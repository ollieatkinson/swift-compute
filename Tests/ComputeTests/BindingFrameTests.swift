import Compute
import Testing

@Suite(.timeLimit(.minutes(1)))
struct BindingFrameTests {
    @Test func plain_values_do_not_need_an_evaluation_stage() {
        let plain: JSON = ["title": "Coffee", "ratings": [1, 2, 3]]
        let nested: JSON = ["nested": [.returns("literal", ["value": 42])]]
        let malformed: JSON = ["{returns}": ["first": 1, "second": 2]]
        let malformedWithProgram: JSON = ["{returns}": ["first": .returns("literal", ["value": 42]), "second": 2]]
        #expect(!JSON.null.requiresEvaluation)
        #expect(!plain.requiresEvaluation)
        #expect(JSON.returns("unknown", [:]).requiresEvaluation)
        #expect(nested.requiresEvaluation)
        #expect(!malformed.requiresEvaluation)
        #expect(malformedWithProgram.requiresEvaluation)
    }

    @Test func a_streaming_keyword_owns_the_initial_snapshot_and_later_changes() async throws {
        let references = TestReferences()
        await references.set("value", to: 1)
        let runtime = Compute.Runtime(document: .returns("stream", [:]), functions: [
            StreamValue(references: references)
        ])
        defer { await runtime.cancel(); await references.finish() }
        var values = runtime.run().makeAsyncIterator()
        #expect(await values.next() == .success(1))
        await references.set("value", to: 2)
        #expect(await values.next() == .success(2))
        #expect(await references.subscriptionCount(for: "value") == 1)
    }
    @Test func an_owned_evaluation_inherits_the_binding_scope() async throws {
        let references = TestReferences()
        await references.set("name?user=\"Dorothy\"", to: "Dorothy")
        let runtime = Compute.Runtime(document: .returns("from", ["reference": "name"]),
            context: .init(scope: ["user": "Dorothy"]),
            functions: [Compute.Keyword.From.Function(references: references)])
        defer { await runtime.cancel(); await references.finish() }
        #expect(try await runtime.value() == "Dorothy")
    }

    @Test func an_owned_evaluation_preserves_the_enclosing_depth_limit() async throws {
        let references = TestReferences()
        await references.set("value", to: 42)
        let runtime = Compute.Runtime(document: .returns("from", ["reference": "value"]),
            depth: 19, functions: [Compute.Keyword.From.Function(references: references)])
        defer { await runtime.cancel(); await references.finish() }
        #expect(try await runtime.value() == 42)
        let tooDeep = Compute.Runtime(document: .returns("literal", ["value": 42]), depth: 20)
        defer { await tooDeep.cancel() }
        await #expect(throws: JSONError.self) { try await tooDeep.value() }
    }

    @Test func an_evaluated_binding_value_keeps_its_data_markers_and_evidence() async throws {
        let data = JSON.returns("error", ["message": "Data, not an operation"])
        let runtime = Compute.Runtime(document: .returns("bound", [:]), depth: 19,
            functions: [BoundValue(data: data)])
        defer { await runtime.cancel() }
        var values = runtime.run(tracing: true).makeAsyncIterator()
        let value = try #require(await values.next())
        #expect(value.result == .success(data))
        #expect(value.thoughts.contains { $0.keyword == "binding_source" && $0.output == data })
        #expect(value.thoughts.contains { $0.keyword == "bound" && $0.depth == 19 })
    }
}

private struct StreamValue: Compute.StreamingKeywordDefinition {
    let references: TestReferences
    var name: String { "stream" }
    func compute(data: JSON, frame: Compute.Frame) async throws -> JSON? {
        throw JSONError("A live stream must own its initial snapshot")
    }
    func subject(data: JSON, frame: Compute.Frame, bufferingPolicy: BufferingPolicy)
        -> AsyncStream<Result<JSON, JSONError>> {
        references.values(for: "value", context: nil)
    }
}

private struct BoundValue: AnyReturnsKeyword {
    let data: JSON
    var name: String { "bound" }
    func compute(data: JSON, frame: Compute.Frame) async throws -> JSON? {
        JSON(Compute.SourceSnapshot.evaluated(self.data, thoughts: [
            .init(route: frame.route, depth: frame.depth, keyword: "binding_source", output: self.data)
        ]))
    }
}
