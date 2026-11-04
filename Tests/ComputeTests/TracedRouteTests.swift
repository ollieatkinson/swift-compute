import Compute
import Testing

@Suite(.timeLimit(.minutes(1)))
struct TracedRouteTests {
    @Test
    func returned_field_results_have_their_own_evidence_before_a_sibling_finishes() async throws {
        let references = TestReferences(initiallyPending: true)
        await references.set("definition", to: source("A", [
            "score": .returns("from", ["reference": "score"]),
            "waiting": .returns("from", ["reference": "waiting"])
        ]))
        await references.set("score", to: 1)
        let runtime = makeRuntime(references)
        defer { await runtime.cancel() }
        var documents = runtime.run(tracing: true).makeAsyncIterator()
        var scores = runtime.run(at: ["score"], tracing: true).makeAsyncIterator()
        var plain = runtime.run(at: ["score"]).makeAsyncIterator()
        let first = try #require(await scores.next())
        try #require(first.result == .success(1))
        try #require(await plain.next() == .success(1))
        #expect(first.thoughts.contains { $0.keyword == "source_evidence" && $0.output == "A" })
        #expect(first.thoughts.contains { $0.keyword == "from" && $0.output == 1 })
        #expect(!first.thoughts
            .contains { $0.input == JSON.returns("from", ["reference": "waiting"]) })
        #expect((try? await references.value(for: "waiting", context: nil)) == nil)
        #expect(await references.subscriptionCount(for: "score") == 1)
        await references.set("score", to: 2)
        let second = try #require(await scores.next())
        try #require(second.result == .success(2))
        #expect(second.thoughts.contains { $0.keyword == "from" && $0.output == 2 })
        #expect(!second.thoughts.contains { $0.keyword == "from" && $0.output == 1 })
        // The first result's evidence is a snapshot, not later runtime state.
        #expect(first.thoughts.contains { $0.keyword == "from" && $0.output == 1 })
        await references.set("waiting", to: "Ready")
        let whole = try #require(await documents.next())
        #expect(whole.result == .success(["score": 2, "waiting": "Ready"]))
        #expect(whole.thoughts.contains { $0.keyword == "from" && $0.output == "Ready" })
    }

    @Test
    func committed_field_evidence_survives_another_routes_failure() async throws {
        let references = TestReferences()
        await references.set("definition", to: source("Profile", [
            "score": .returns("from", ["reference": "score"]),
            "broken": .returns("error", ["message": "Profile unavailable"])
        ]))
        await references.set("score", to: 1)
        await references.set("other", to: 0)
        let runtime = Compute.Runtime(document: [
            "a_other": .returns("from", ["reference": "other"]),
            "profile": .returns("from", ["reference": "definition"])
        ], functions: [Compute.Keyword.From.Function(references: references), RecordedSource()])
        defer { await runtime.cancel() }
        var documents = runtime.run(tracing: true).makeAsyncIterator()
        var scores = runtime.run(at: ["profile", "score"], tracing: true).makeAsyncIterator()
        try #require(await documents.next()?.result == .failure(JSONError("Profile unavailable")))
        let first = try #require(await scores.next())
        try #require(first.result == .success(1))
        #expect(first.thoughts.contains { $0.output == "Profile" })
        await references.fail("other", with: JSONError("Other unavailable"))
        let changed = try #require(await documents.next())
        try #require(changed.result == .failure(JSONError("Other unavailable")))
        // The untouched source's committed evidence stays available to the root.
        #expect(changed.thoughts
            .contains { $0.keyword == "source_evidence" && $0.output == "Profile" })
        await references.set("score", to: 2)
        let second = try #require(await scores.next())
        try #require(second.result == .success(2))
        #expect(second.thoughts
            .contains { $0.keyword == "source_evidence" && $0.output == "Profile" })
        #expect(!second.thoughts
            .contains { $0.input == JSON.returns("from", ["reference": "other"]) })
    }

    @Test
    func replacement_pairs_new_field_values_with_new_source_evidence() async throws {
        let references = TestReferences(initiallyPending: true)
        await references.set("definition", to: source("Old", [
            "score": .returns("from", ["reference": "old"]),
            "waiting": .returns("from", ["reference": "waiting"])
        ]))
        await references.set("old", to: 1)
        await references.set("new", to: 2)
        let runtime = makeRuntime(references)
        defer { await runtime.cancel() }
        let root = Task { for await _ in runtime.run(tracing: true) {} }
        defer { root.cancel() }
        var scores = runtime.run(at: ["score"], tracing: true).makeAsyncIterator()
        let first = try #require(await scores.next())
        try #require(first.result == .success(1))
        #expect(first.thoughts.contains { $0.keyword == "source_evidence" && $0.output == "Old" })
        await references.set("definition", to: source("New", [
            "score": .returns("from", ["reference": "new"])
        ]))
        let second = try #require(await scores.next())
        try #require(second.result == .success(2))
        #expect(second.thoughts.contains { $0.keyword == "source_evidence" && $0.output == "New" })
        #expect(!second.thoughts.contains { $0.keyword == "source_evidence" && $0.output == "Old" })
        await references.set("old", to: 99)
        await references.set("new", to: 3)
        let third = try #require(await scores.next())
        try #require(third.result == .success(3))
        await runtime.cancel()
        #expect(await scores.next() == nil)
    }

    @Test
    func explicit_routes_and_detached_frame_work_keep_their_output_ownership() async throws {
        let runtime = Compute.Runtime(document: [
            "left": .returns("detached_trace", [:]),
            "right": .returns("literal", ["value": "Unrelated"])
        ], functions: [DetachedTrace()])
        defer { await runtime.cancel() }
        var documents = runtime.run(tracing: true).makeAsyncIterator()
        var left = runtime.run(at: ["left"], tracing: true).makeAsyncIterator()
        let captured = try #require(await left.next())
        try #require(captured.result == .success(42))
        #expect(captured.thoughts.contains { $0.route == ["outside"] && $0.output == 42 })
        #expect(captured.thoughts.contains { $0.route == ["external"] && $0.output == "Recorded" })
        #expect(!captured.thoughts.contains { $0.route == ["right"] })
        #expect(await documents.next()?.result == .success(["left": 42, "right": "Unrelated"]))
    }

    @Test(arguments: [false, true])
    func tracing_keeps_defaults_atomic_and_opaque_values_inert(opaque: Bool) async throws {
        let deferred = JSON.returns("error", ["message": "Deferred"])
        let value = opaque ? JSON.returns("literal", ["value": ["score": deferred]])
            : JSON.returns("error", ["message": "Use fallback"], default: ["score": 7])
        let references = TestReferences()
        await references.set("definition", to: value)
        let runtime = makeRuntime(references)
        defer { await runtime.cancel() }
        var scores = runtime.run(at: ["score"], tracing: true).makeAsyncIterator()
        let first = try #require(await scores.next())
        #expect(first.result == .success(opaque ? deferred : 7))
        #expect(!first.thoughts.isEmpty)
        if opaque { #expect(!first.thoughts.contains { $0.keyword == "error" }) }
    }

    @Test
    func trace_only_changes_publish_new_evidence_without_replaying_plain_values() async throws {
        let references = TestReferences()
        await references.set("definition", to: source("A", ["score": 1]))
        let runtime = makeRuntime(references)
        defer { await runtime.cancel() }
        var traced = runtime.run(at: ["score"], tracing: true).makeAsyncIterator()
        var plain = runtime.run(at: ["score"]).makeAsyncIterator()
        try #require(await traced.next()?.result == .success(1))
        try #require(await plain.next() == .success(1))
        await references.set("definition", to: source("B", ["score": 1]))
        let changed = try #require(await traced.next())
        try #require(changed.result == .success(1))
        #expect(changed.thoughts.contains { $0.keyword == "source_evidence" && $0.output == "B" })
        await references.set("definition", to: source("B", ["score": 2]))
        try #require(await traced.next()?.result == .success(2))
        // No extra identical value was queued merely because a tracer was present.
        try #require(await plain.next() == .success(2))
    }

    @Test
    func negative_indices_keep_the_current_elements_evidence_and_unselected_code_inert(
    ) async throws {
        let references = TestReferences()
        await references.set("definition", to: [
            source("Unrequested", ["score": .returns("from", ["reference": "unused"])]),
            source("First", ["score": 1])
        ])
        let runtime = makeRuntime(references)
        defer { await runtime.cancel() }
        var scores = runtime.run(at: [.index(-1), "score"], tracing: true).makeAsyncIterator()
        let first = try #require(await scores.next())
        try #require(first.result == .success(1))
        #expect(first.thoughts.contains { $0.keyword == "source_evidence" && $0.output == "First" })
        #expect(!first.thoughts
            .contains { $0.keyword == "source_evidence" && $0.output == "Unrequested" })
        await references.set("definition", to: [source("Next", ["score": 2])])
        let second = try #require(await scores.next())
        try #require(second.result == .success(2))
        #expect(second.thoughts.contains { $0.keyword == "source_evidence" && $0.output == "Next" })
        #expect(!second.thoughts
            .contains { $0.keyword == "source_evidence" && $0.output == "First" })
        #expect(await references.subscriptionCount(for: "unused") == 0)
    }

    @Test
    func tracing_does_not_prune_inside_an_opaque_source_adapter() async throws {
        let references = TestReferences()
        await references.set("definition", to: source("Atomic", [
            "score": 1,
            "broken": .returns("error", ["message": "Required by opaque operation"])
        ]))
        let runtime = Compute.Runtime(
            document: .returns("from", ["reference": "definition"]),
            functions: [
                Compute.Keyword.From.Function(references: references),
                OpaqueSource()
            ]
        )
        defer { await runtime.cancel() }
        var scores = runtime.run(at: ["score"], tracing: true).makeAsyncIterator()
        let first = try #require(await scores.next())
        #expect(first.result == .failure(JSONError("Required by opaque operation")))
        #expect(first.thoughts
            .contains { $0.keyword == "source_evidence" && $0.output == "Atomic" })
    }

    @Test
    func ending_a_tracer_keeps_the_plain_observers_source_and_updates_alive() async throws {
        let references = TestReferences()
        await references.set("definition", to: ["score": .returns("from", ["reference": "score"])])
        await references.set("score", to: 1)
        let runtime = makeRuntime(references)
        defer { await runtime.cancel() }
        let (seen, ready) = AsyncStream.makeStream(
            of: Bool.self,
            bufferingPolicy: .bufferingNewest(1)
        )
        let tracer = Task {
            for await _ in runtime.run(at: ["score"], tracing: true) { ready.yield(true) }
            ready.finish()
        }
        defer { tracer.cancel() }
        var started = seen.makeAsyncIterator()
        try #require(await started.next() == true)
        var plain = runtime.run(at: ["score"]).makeAsyncIterator()
        try #require(await plain.next() == .success(1))
        #expect(await references.subscriptionCount(for: "score") == 1)
        tracer.cancel()
        await tracer.value
        await references.set("score", to: 2)
        try #require(await plain.next() == .success(2))
        #expect(await references.subscriptionCount(for: "score") == 1)
        await runtime.cancel()
        #expect(await plain.next() == nil)
    }

    private func source(_ marker: JSON, _ value: JSON) -> JSON {
        .returns("recorded_source", ["marker": marker, "value": value])
    }

    private func makeRuntime(_ references: TestReferences) -> Compute.Runtime {
        Compute.Runtime(
            document: .returns("from", ["reference": "definition"]),
            functions: [
                Compute.Keyword.From.Function(references: references),
                RecordedSource()
            ]
        )
    }
}

private struct RecordedSource: AnyReturnsKeyword {
    let name = "recorded_source"
    func compute(data: JSON, frame: Compute.Frame) async throws -> JSON? {
        await frame.record(Compute.Thought(
            route: ["source"],
            depth: frame.depth,
            keyword: "source_evidence",
            output: data["marker"]
        ))
        return data["value"]
    }
}

private struct DetachedTrace: Compute.OpaqueOutputKeyword {
    let name = "detached_trace"
    func compute(data: JSON, frame: Compute.Frame) async throws -> JSON? {
        let scoped = frame.scoped(to: ["user": "Dorothy"])["child"]
        return try await Task.detached {
            let value = try await scoped.compute(
                .returns("literal", ["value": 42]),
                at: ["outside"]
            )
            await scoped.record(Compute.Thought(
                route: ["external"],
                depth: frame.depth,
                keyword: "recorded",
                output: "Recorded"
            ))
            return value
        }.value
    }
}

private struct OpaqueSource: Compute.OpaqueOutputKeyword {
    let name = "recorded_source"
    func compute(data: JSON, frame: Compute.Frame) async throws -> JSON? {
        let program = try #require(await RecordedSource().compute(data: data, frame: frame))
        return try await frame.compute(program, at: frame.route.appending(.key("value")))
    }
}
