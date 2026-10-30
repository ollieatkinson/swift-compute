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

    @Test func explicit_null_is_preserved_and_a_missing_value_is_an_error() async throws {
        try await expect(.returns("literal", ["value": .null]), equals: .null)
        await expectJSONError(containing: "value") {
            _ = try await value(.returns("literal", [:]))
        }
    }
}
