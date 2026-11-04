import Compute
import Testing

@Suite(.timeLimit(.minutes(1)))
struct ReturnedFieldTests {
    @Test(arguments: [false, true])
    func field_observers_share_sources_and_keep_updating_beside_a_failed_sibling(
        returned: Bool
    ) async throws {
        let references = TestReferences()
        let definition: JSON = [
            "subtitle": "child",
            "score": .returns("from", ["reference": "score"]),
            "unrelated": .returns("from", ["reference": "unrelated"])
        ]
        await references.set("definition", to: definition)
        await references.set("score", to: 1)
        await references.set("unrelated", to: 9)
        let runtime = Compute.Runtime(
            document: returned ? .returns("from", ["reference": "definition"]) : definition,
            functions: [Compute.Keyword.From.Function(references: references)]
        )
        defer { await runtime.cancel() }
        var documents = runtime.run().makeAsyncIterator()
        var scores = runtime.run(at: ["score"]).makeAsyncIterator()
        try #require(await documents.next() == .success([
            "subtitle": "child",
            "score": 1,
            "unrelated": 9
        ]))
        try #require(await scores.next() == .success(1))
        #expect(await references.subscriptionCount(for: "score") == 1)
        await references.fail("unrelated", with: JSONError("Unavailable sibling"))
        guard case .failure = await documents.next() else {
            Issue.record("The whole document must retain its failure")
            return
        }
        await references.set("score", to: 2)
        try #require(await scores.next() == .success(2))
        await references.set("unrelated", to: 10)
        try #require(await documents.next() == .success([
            "subtitle": "child",
            "score": 2,
            "unrelated": 10
        ]))
        #expect(await references.subscriptionCount(for: "score") == 1)
        await runtime.cancel()
        #expect(await documents.next() == nil)
        #expect(await scores.next() == nil)
    }

    @Test(arguments: [false, true])
    func selecting_a_field_does_not_evaluate_an_unrequested_returned_sibling(
        returned: Bool
    ) async throws {
        let references = TestReferences()
        let definition: JSON = [
            "score": .returns("from", ["reference": "score"]),
            "unrelated": .returns("from", ["reference": "unrelated"])
        ]
        await references.set("definition", to: definition)
        await references.set("score", to: 1)
        await references.fail("unrelated", with: JSONError("Must remain inert"))
        let runtime = Compute.Runtime(
            document: returned ? .returns("from", ["reference": "definition"]) : definition,
            functions: [Compute.Keyword.From.Function(references: references)]
        )
        defer { await runtime.cancel() }
        var scores = runtime.run(at: ["score"]).makeAsyncIterator()
        try #require(await scores.next() == .success(1))
        #expect(await references.subscriptionCount(for: "unrelated") == 0)
        await references.set("score", to: 2)
        try #require(await scores.next() == .success(2))
    }

    @Test
    func a_committed_field_survives_another_routes_failure() async throws {
        let references = TestReferences()
        await references.set("definition", to: [
            "score": .returns("from", ["reference": "score"]),
            "unrelated": .returns("error", ["message": "Profile unavailable"])
        ])
        await references.set("score", to: 1)
        await references.set("other", to: 0)
        let runtime = Compute.Runtime(document: [
            "a_other": .returns("from", ["reference": "other"]),
            "profile": .returns("from", ["reference": "definition"])
        ], functions: [Compute.Keyword.From.Function(references: references)])
        defer { await runtime.cancel() }
        var documents = runtime.run().makeAsyncIterator()
        var scores = runtime.run(at: ["profile", "score"]).makeAsyncIterator()
        try #require(await documents.next() == .failure(JSONError("Profile unavailable")))
        try #require(await scores.next() == .success(1))
        await references.fail("other", with: JSONError("Other unavailable"))
        try #require(await documents.next() == .failure(JSONError("Other unavailable")))
        await references.set("score", to: 2)
        try #require(await scores.next() == .success(2))
    }

    @Test
    func a_field_progresses_while_the_returned_document_waits_and_survives_root_cancellation(
    ) async throws {
        let references = TestReferences(initiallyPending: true)
        await references.set("definition", to: [
            "a_waiting": .returns("from", ["reference": "waiting"]),
            "score": .returns("from", ["reference": "score"])
        ])
        await references.set("score", to: 1)
        let runtime = Compute.Runtime(
            document: .returns("from", ["reference": "definition"]),
            functions: [Compute.Keyword.From
                .Function(references: references)]
        )
        defer { await runtime.cancel() }
        let whole = Task { for await _ in runtime.run() {} }
        defer { whole.cancel() }
        try await wait { await references.subscriptionCount(for: "waiting") == 1 }
        var scores = runtime.run(at: ["score"]).makeAsyncIterator()
        try #require(await scores.next() == .success(1))
        #expect((try? await references.value(for: "waiting", context: nil)) == nil)
        await references.set("score", to: 2)
        try #require(await scores.next() == .success(2))
        whole.cancel()
        await whole.value
        try await wait { await references.subscriptionCount(for: "waiting") == 0 }
        await references.set("score", to: 3)
        try #require(await scores.next() == .success(3))
        #expect(await references.subscriptionCount(for: "score") == 1)
        await runtime.cancel()
        try await wait { await references.subscriptionCount(for: "score") == 0 }
        #expect(await scores.next() == nil)
    }

    @Test
    func returned_fields_replace_same_depth_dependencies_and_report_missing_before_sibling_errors(
    ) async throws {
        let references = TestReferences()
        await references.set("definition", to: [
            "score": .returns("from", ["reference": "old"]),
            "subtitle": "first"
        ])
        await references.set("old", to: 1)
        await references.set("new", to: 2)
        let runtime = Compute.Runtime(
            document: .returns("from", ["reference": "definition"]),
            functions: [Compute.Keyword.From
                .Function(references: references)]
        )
        defer { await runtime.cancel() }
        var documents = runtime.run().makeAsyncIterator()
        var scores = runtime.run(at: ["score"]).makeAsyncIterator()
        try #require(await documents.next() == .success(["score": 1, "subtitle": "first"]))
        try #require(await scores.next() == .success(1))
        await references.set("definition", to: [
            "score": .returns("from", ["reference": "new"]),
            "subtitle": "second"
        ])
        try #require(await documents.next() == .success(["score": 2, "subtitle": "second"]))
        try #require(await scores.next() == .success(2))
        try await wait { await references.subscriptionCount(for: "old") == 0 }
        await references.set("new", to: 3)
        try #require(await documents.next() == .success(["score": 3, "subtitle": "second"]))
        try #require(await scores.next() == .success(3))
        await references.set("definition", to: [
            "unrelated": .returns("error", ["message": "Unavailable sibling"])
        ])
        try #require(await scores.next() == .failure(JSONError("Missing value", path: ["score"])))
        try #require(await documents.next() == .failure(JSONError("Unavailable sibling")))
        try await wait { await references.subscriptionCount(for: "new") == 0 }
        await references.set("definition", to: ["score": 4])
        try #require(await scores.next() == .success(4))
        try #require(await documents.next() == .success(["score": 4]))
    }

    @Test
    func negative_indices_follow_returned_shape_without_evaluating_other_elements() async throws {
        let references = TestReferences()
        let unused = JSON.returns("from", ["reference": "unused"])
        await references.set("definition", to: [unused, ["title": "first"]])
        let runtime = Compute.Runtime(
            document: .returns("from", ["reference": "definition"]),
            functions: [Compute.Keyword.From
                .Function(references: references)]
        )
        defer { await runtime.cancel() }
        var titles = runtime.run(at: [.index(-1), "title"]).makeAsyncIterator()
        try #require(await titles.next() == .success("first"))
        await references.set("definition", to: [unused, unused, ["title": "second"]])
        try #require(await titles.next() == .success("second"))
        await references.set("definition", to: [])
        try #require(await titles.next() == .failure(JSONError(
            "Missing value",
            path: ["-1", "title"]
        )))
        await references.set("definition", to: [["title": "third"]])
        try #require(await titles.next() == .success("third"))
        #expect(await references.subscriptionCount(for: "unused") == 0)
    }

    @Test(arguments: [false, true])
    func whole_reads_still_evaluate_all_returned_fields_beside_a_field_observer(
        stepping: Bool
    ) async throws {
        let references = TestReferences()
        await references.set("definition", to: [
            "score": .returns("from", ["reference": "score"]),
            "unrelated": .returns("error", ["message": "Whole failure"])
        ])
        await references.set("score", to: 1)
        let runtime = Compute.Runtime(
            document: .returns("from", ["reference": "definition"]),
            functions: [Compute.Keyword.From
                .Function(references: references)]
        )
        defer { await runtime.cancel() }
        var scores = runtime.run(at: ["score"]).makeAsyncIterator()
        try #require(await scores.next() == .success(1))
        do {
            if stepping { _ = try await runtime.step() }
            else { _ = try await runtime.value() }
            Issue.record("A whole read must evaluate its failed sibling")
        } catch { #expect(JSONError(error) == JSONError("Whole failure")) }
        await references.set("score", to: 2)
        try #require(await scores.next() == .success(2))
    }

    @Test(arguments: [false, true])
    func fallback_selection_is_atomic_and_literal_fields_remain_data(topLevel: Bool) async throws {
        let references = TestReferences()
        let deferred = JSON.returns("error", ["message": "Deferred data"])
        let choice = JSON.returns("from", ["reference": "choice"], default: ["score": "fallback"])
        await references.set("choice", to: [
            "score": "discarded",
            "unrelated": .returns("error", ["message": "Choose fallback"])
        ])
        await references.set("definition", to: topLevel ? choice : ["nested": choice])
        let runtime = Compute.Runtime(
            document: .returns("from", ["reference": "definition"]),
            functions: [Compute.Keyword.From
                .Function(references: references)]
        )
        defer { await runtime.cancel() }
        let path: Compute.Route = topLevel ? ["score"] : ["nested", "score"]
        var scores = runtime.run(at: path).makeAsyncIterator()
        try #require(await scores.next() == .success("fallback"))
        await references.set("choice", to: .returns("literal", ["value": ["score": deferred]]))
        try #require(await scores.next() == .success(deferred))
    }

    @Test
    func replacing_a_pending_definition_retires_its_sources_before_late_values() async throws {
        let references = TestReferences(initiallyPending: true)
        await references.set("definition", to: [
            "score": .returns("from", ["reference": "old"]),
            "waiting": .returns("from", ["reference": "waiting"])
        ])
        await references.set("old", to: 1)
        await references.set("new", to: 2)
        let runtime = Compute.Runtime(
            document: .returns("from", ["reference": "definition"]),
            functions: [Compute.Keyword.From
                .Function(references: references)]
        )
        defer { await runtime.cancel() }
        var documents = runtime.run().makeAsyncIterator()
        var scores = runtime.run(at: ["score"]).makeAsyncIterator()
        try #require(await scores.next() == .success(1))
        try await wait { await references.subscriptionCount(for: "waiting") == 1 }
        await references.set("definition", to: ["score": .returns("from", ["reference": "new"])])
        try #require(await documents.next() == .success(["score": 2]))
        try #require(await scores.next() == .success(2))
        try await wait { await references.subscriptionCount(for: "waiting") == 0 }
        try await wait { await references.subscriptionCount(for: "old") == 0 }
        await references.set("old", to: 99)
        await references.set("waiting", to: "Obsolete")
        await references.set("new", to: 3)
        try #require(await scores.next() == .success(3))
        try #require(await documents.next() == .success(["score": 3]))
    }

    @Test
    func projected_branches_preserve_native_cycle_diagnostics_and_explanation_scope() async throws {
        let references = TestReferences()
        let explanation: JSON = .returns("explain", [
            "value": .returns("from", ["reference": "name"])
        ])
        await references.set("name", to: "Dorothy")
        await references.set("definition", to: [
            "good": explanation,
            "loop": .returns("from", ["reference": "definition"])
        ])
        let runtime = Compute.Runtime(
            document: .returns("from", ["reference": "definition"]),
            functions: [Compute.Keyword.From
                .Function(references: references)]
        )
        defer { await runtime.cancel() }
        var documents = runtime.run().makeAsyncIterator()
        var good = runtime.run(at: ["good"]).makeAsyncIterator()
        guard case .failure(let error) = await documents.next() else {
            Issue.record("Expected a native reference cycle")
            return
        }
        #expect(error.message == "Reference cycle: definition -> definition")
        let captured = try #require(await good.next()).get()
        #expect(captured.object?["value"] == "Dorothy")
        let thoughts = try #require(captured["thoughts"].array)
        #expect(thoughts.count == 1)
        #expect(thoughts.allSatisfy { $0["keyword"] == "from" })
        await references.set("definition", to: ["good": explanation, "loop": "Recovered"])
        let recovered = try #require(await documents.next()).get()
        #expect(recovered["good"] == captured && recovered["loop"] == "Recovered")
    }

    private func wait(_ condition: @Sendable () async -> Bool) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(5))
        while !(await condition()) {
            try Task.checkCancellation()
            guard ContinuousClock.now < deadline
            else { throw JSONError("Source lifetime did not settle") }
            try await Task.sleep(for: .milliseconds(1))
        }
    }
}
