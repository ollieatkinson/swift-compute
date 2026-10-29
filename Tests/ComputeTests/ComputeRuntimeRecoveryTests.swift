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

    @Test func concurrent_independent_branches_keep_both_replacement_dependencies() async throws {
        let references = TestReferences()
        await references.set("left", to: ["{returns}": ["from": ["reference": "old_left"]]])
        await references.set("right", to: ["{returns}": ["from": ["reference": "old_right"]]])
        await references.set("old_left", to: "L0")
        await references.set("old_right", to: "R0")
        await references.set("new_left", to: "L1")
        await references.set("new_right", to: "R1")
        let runtime = try runtime([
            "left": ["{returns}": ["from": ["reference": "left"]]],
            "right": ["{returns}": ["from": ["reference": "right"]]],
        ], references: references)
        defer { await runtime.cancel() }
        var values = runtime.run().makeAsyncIterator()
        await expectNext(&values, equals: .success(["left": "L0", "right": "R0"]))

        async let left: Void = references.set("left", to: ["{returns}": ["from": ["reference": "new_left"]]])
        async let right: Void = references.set("right", to: ["{returns}": ["from": ["reference": "new_right"]]])
        _ = await (left, right)
        var bothReplaced = false
        while let value = try await values.next()?.get() {
            if value == ["left": "L1", "right": "R1"] { bothReplaced = true; break }
        }
        try #require(bothReplaced)
        await references.set("new_left", to: "L2")
        await expectNext(&values, equals: .success(["left": "L2", "right": "R1"]))
        await references.set("new_right", to: "R2")
        await expectNext(&values, equals: .success(["left": "L2", "right": "R2"]))
    }
}
