import Compute
import Testing

@Suite(.timeLimit(.minutes(1))) struct LiteralTests {
    @Test func nested_expressions_remain_data_in_objects_and_arrays() async throws {
        let deferred: JSON = .returns("error", ["message": "Deferred intent"])
        let payload: JSON = ["input": deferred, "rows": [deferred, .null]]
        try await expect(.returns("literal", ["value": payload]), equals: payload)
    }

    @Test func returned_literals_and_get_do_not_re_evaluate_selected_data() async throws {
        let deferred: JSON = .returns("error", ["message": "Deferred intent"])
        let references = TestReferences()
        await references.set("derived", to: .returns("literal", ["value": ["input": deferred]]))
        let runtime = try runtime(.returns("get", [
            "value": .returns("from", ["reference": "derived"]), "path": ["input"],
        ]), references: references)
        defer { await runtime.cancel(); await references.finish() }
        #expect(try await runtime.value() == deferred)
    }

    @Test func an_opaque_expression_is_complete_after_one_step() async throws {
        let deferred = JSON.returns("error", ["message": "Deferred intent"])
        let runtime = try runtime(.returns("literal", ["value": deferred]))
        defer { await runtime.cancel() }
        let step = try await runtime.step()
        #expect(step.state == deferred)
        #expect(step.remainingThoughts == 0)
        #expect(!step.isThinking)
    }

    @Test func independent_routes_stop_counting_when_opaque_results_have_settled() async throws {
        let deferred = JSON.returns("error", ["message": "Deferred intent"])
        let runtime = try runtime([
            "first": .returns("literal", ["value": deferred]),
            "second": .returns("literal", ["value": 42])
        ])
        defer { await runtime.cancel() }
        #expect(await runtime.remainingThoughtCount == 2)
        let final = try await runtime.step()
        #expect(final.remainingThoughts == 0)
        #expect(final.state == ["first": deferred, "second": 42])
    }

    @Test func live_returned_literals_emit_opaque_results_and_follow_replacements() async throws {
        let references = TestReferences()
        let first = JSON.returns("error", ["message": "First is data"])
        let second = JSON.returns("from", ["reference": "Must stay deferred"])
        await references.set("result", to: .returns("literal", ["value": first]))
        let runtime = try runtime(.returns("from", ["reference": "result"]), references: references)
        defer { await runtime.cancel(); await references.finish() }
        var values = runtime.run().makeAsyncIterator()
        #expect(await values.next() == .success(first))
        await references.set("result", to: .returns("literal", ["value": second]))
        #expect(await values.next() == .success(second))
        await references.set("result", to: .returns("literal", ["value": .null]))
        #expect(await values.next() == .success(.null))
    }

    @Test func explicit_null_is_preserved_and_a_missing_value_is_an_error() async throws {
        try await expect(.returns("literal", ["value": .null]), equals: .null)
        await expectJSONError(containing: "value") {
            _ = try await value(.returns("literal", [:]))
        }
    }
}
