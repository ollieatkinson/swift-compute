import Compute
import Testing

@Suite(.timeLimit(.minutes(1)))
struct ComputeRuntimePendingTests {
    @Test(arguments: [false, true])
    func a_parent_can_replace_a_returned_expression_while_its_input_is_pending(initiallyLoaded: Bool) async throws {
        let references = TestReferences(initiallyPending: true)
        let pending = JSON.returns("from", ["reference": "pending"])
        await references.set("definition", to: initiallyLoaded ? "Initial" : pending)
        let runtime = try runtime(.returns("from", ["reference": "definition"]),
            references: WaitingReferences(base: references))
        defer { await runtime.cancel() }
        var values = runtime.run().makeAsyncIterator()
        if initiallyLoaded {
            await expectNext(&values, equals: .success("Initial"))
            await references.set("definition", to: pending)
        }
        try await wait { await references.subscriptionCount(for: "pending") > 0 }
        await references.set("definition", to: "Current")
        await expectNext(&values, equals: .success("Current"))
        try await wait { await references.subscriptionCount(for: "pending") == 0 }
        await references.set("pending", to: "Too late")
        await references.set("definition", to: "Still current")
        await expectNext(&values, equals: .success("Still current"))
    }

    @Test
    func cancelling_a_pending_run_releases_its_read_and_allows_a_fresh_run() async throws {
        let references = TestReferences(initiallyPending: true)
        await references.set("definition", to: .returns("from", ["reference": "pending"]))
        let runtime = try runtime(.returns("from", ["reference": "definition"]),
            references: WaitingReferences(base: references))
        defer { await runtime.cancel() }
        var values = runtime.run().makeAsyncIterator()
        try await wait { await references.subscriptionCount(for: "pending") > 0 }
        await runtime.cancel()
        #expect(await values.next() == nil)
        try await wait { await references.subscriptionCount(for: "pending") == 0 }
        await references.set("definition", to: "Restarted")
        var restarted = runtime.run().makeAsyncIterator()
        await expectNext(&restarted, equals: .success("Restarted"))
    }

    @Test
    func nested_definition_changes_and_independent_branches_survive_interrupted_waves() async throws {
        let references = TestReferences(initiallyPending: true)
        await references.set("left", to: .returns("from", ["reference": "definition"]))
        await references.set("definition", to: .returns("from", ["reference": "pending"]))
        await references.set("right", to: "R0")
        let runtime = try runtime([
            "left": .returns("from", ["reference": "left"]),
            "right": .returns("from", ["reference": "right"])
        ], references: WaitingReferences(base: references))
        defer { await runtime.cancel() }
        var values = runtime.run().makeAsyncIterator()
        try await wait { await references.subscriptionCount(for: "pending") > 0 }
        await references.set("right", to: "R1")
        await references.set("definition", to: "L1")
        await expectNext(&values, equals: .success(["left": "L1", "right": "R1"]))
        await references.set("right", to: "R2")
        await expectNext(&values, equals: .success(["left": "L1", "right": "R2"]))
    }

    private func wait(_ condition: @Sendable () async -> Bool) async throws {
        while !(await condition()) {
            try Task.checkCancellation()
            await Task.yield()
        }
    }
}

private struct WaitingReferences: Compute.AsyncReferences {
    let base: TestReferences

    func value(for reference: JSON, context: [String: JSON]?) async throws -> JSON {
        var values = base.values(for: reference, context: context).makeAsyncIterator()
        guard let result = await values.next() else { throw CancellationError() }
        return try result.get()
    }

    func values(for reference: JSON, context: [String: JSON]?) -> AsyncStream<Result<JSON, JSONError>> {
        base.values(for: reference, context: context)
    }
}
