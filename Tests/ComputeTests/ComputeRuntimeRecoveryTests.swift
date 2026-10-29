import Compute
import Testing

@Suite(.timeLimit(.minutes(1))) struct ComputeRuntimeRecoveryTests {
    @Test func a_reference_missing_on_the_first_read_can_appear_without_a_default() async throws {
        let references = TestReferences()
        let runtime = try runtime(["{returns}": ["from": ["reference": "name"]]], references: references)
        defer { await runtime.cancel() }
        var values = runtime.run().makeAsyncIterator()
        if case .failure = await values.next() {} else { Issue.record("Expected the initial missing reference") }

        await references.set("name", to: "Dorothy")
        await expectNext(&values, equals: .success("Dorothy"))
        await references.fail("name", with: JSONError("offline"))
        await expectNext(&values, equals: .failure(JSONError("offline")))
        await references.set("name", to: "Restored")
        await expectNext(&values, equals: .success("Restored"))
    }

    @Test func an_initial_failure_in_a_nested_expression_retains_its_dependency() async throws {
        let references = TestReferences()
        await references.fail("name", with: JSONError("offline"))
        let runtime = try runtime([
            "card": ["text": ["{returns}": ["from": ["reference": "name"]]]],
        ], references: references)
        defer { await runtime.cancel() }
        var values = runtime.run().makeAsyncIterator()
        await expectNext(&values, equals: .failure(JSONError("offline")))
        await references.set("name", to: "Dorothy")
        await expectNext(&values, equals: .success(["card": ["text": "Dorothy"]]))
    }
}
