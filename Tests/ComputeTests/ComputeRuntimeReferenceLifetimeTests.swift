import Compute
import Testing

@Suite(.timeLimit(.minutes(1)))
struct ComputeRuntimeReferenceLifetimeTests {
    @Test(arguments: [false, true], [false, true])
    func different_depths_share_the_reference_input_but_keep_their_local_items(
        tracing: Bool,
        useAlias: Bool
    ) async throws {
        let references = StreamReferences()
        let template = JSON.returns("from", ["reference": "template"])
        let shallow = useAlias ? JSON.returns("from", ["reference": "template_alias"]) : template
        let localName = JSON.returns("item", ["name"])
        await references.base.set("template", to: localName)
        await references.base.set("wrapper", to: .returns("map", [
            "src": ["name": "Far"],
            "dst": template,
        ]))
        let runtime = try runtime([
            "shallow": .returns("map", ["src": ["name": "Near"], "dst": shallow]),
            "deep": .returns("from", ["reference": "wrapper"]),
        ], references: references)
        defer {
            await runtime.cancel()
            await references.base.finish()
        }
        var values = runtime.run(tracing: tracing).makeAsyncIterator()
        #expect(await values.next()?.result == .success(["shallow": "Near", "deep": "Far"]))
        #expect(await references.base.subscriptionCount(for: "template") == 1)
        #expect(await references.openings == 2)

        await references.base.set("template", to: ["name": localName, "updated": true])
        #expect(await values.next()?.result == .success([
            "shallow": ["name": "Near", "updated": true],
            "deep": ["name": "Far", "updated": true],
        ]))
        #expect(await references.base.subscriptionCount(for: "template") == 1)

        // Retiring one use must not release the input still used by its sibling.
        await references.base.set("wrapper", to: "Finished")
        #expect(await values.next()?.result == .success([
            "shallow": ["name": "Near", "updated": true],
            "deep": "Finished",
        ]))
        await references.base.set("template", to: localName)
        #expect(await values.next()?.result == .success(["shallow": "Near", "deep": "Finished"]))
        #expect(await references.openings == 2)
        await runtime.cancel()
        try await wait { await references.base.subscriptionCount(for: "template") == 0 }
        try await wait { await references.base.subscriptionCount(for: "wrapper") == 0 }
    }

    @Test(arguments: [false, true])
    func a_live_reference_keeps_its_initial_stream_through_updates_and_cancellation(
        initiallyFailed: Bool
    ) async throws {
        let references = StreamReferences()
        if initiallyFailed {
            await references.base.fail("title", with: JSONError("Initial failure"))
        } else { await references.base.set("title", to: "Initial") }
        let runtime = try runtime(.returns("from", ["reference": "title"]), references: references)
        defer { await runtime.cancel() }
        var values = runtime.run().makeAsyncIterator()
        await expectNext(
            &values,
            equals: initiallyFailed ? .failure(JSONError("Initial failure")) : .success("Initial")
        )
        await references.base.set("title", to: "Updated")
        await expectNext(&values, equals: .success("Updated"))
        #expect(await references.reads == 0)
        #expect(await references.openings == 1)
        await references.base.fail("title", with: JSONError("Unavailable"))
        await expectNext(&values, equals: .failure(JSONError("Unavailable")))
        await references.base.set("title", to: "Recovered")
        await expectNext(&values, equals: .success("Recovered"))
        #expect(await references.openings == 1)
        await runtime.cancel()
        try await wait { await references.base.subscriptionCount(for: "title") == 0 }
    }

    @Test
    func simultaneous_uses_share_the_first_stream_and_restart_after_cancellation() async throws {
        let references = StreamReferences()
        await references.base.set("title", to: "Initial")
        let from = JSON.returns("from", ["reference": "title"])
        let runtime = try runtime(["left": from, "right": from], references: references)
        defer { await runtime.cancel() }
        var values = runtime.run().makeAsyncIterator()
        await expectNext(&values, equals: .success(["left": "Initial", "right": "Initial"]))
        #expect(await references.openings == 1)
        await runtime.cancel()
        try await wait { await references.base.subscriptionCount(for: "title") == 0 }
        await references.base.set("title", to: "Fresh")
        var fresh = runtime.run().makeAsyncIterator()
        await expectNext(&fresh, equals: .success(["left": "Fresh", "right": "Fresh"]))
        #expect(await references.openings == 2)
        #expect(await references.reads == 0)
    }

    @Test
    func one_shot_reads_still_use_the_reference_value_contract() async throws {
        let references = StreamReferences()
        await references.base.set("title", to: "Initial")
        let runtime = try runtime(.returns("from", ["reference": "title"]), references: references)
        #expect(try await runtime.value() == "Initial")
        #expect(await references.reads == 1)
        #expect(await references.openings == 1)
        try await wait { await references.base.subscriptionCount(for: "title") == 0 }
    }

    @Test
    func a_reference_stream_finishing_without_a_snapshot_reports_a_failure() async throws {
        let runtime = try runtime(
            .returns("from", ["reference": "empty"]),
            references: EndedReferences()
        )
        defer { await runtime.cancel() }
        var values = runtime.run().makeAsyncIterator()
        await expectNext(
            &values,
            equals: .failure(JSONError("Reference source finished without a value"))
        )
    }

    @Test
    func removing_the_last_observer_releases_a_pending_initial_subscription() async throws {
        let references = StreamReferences(initiallyPending: true)
        let runtime = try runtime(.returns("from", ["reference": "title"]), references: references)
        defer { await runtime.cancel() }
        let observation = Task {
            for await _ in runtime.run() {}
        }
        try await wait { await references.base.subscriptionCount(for: "title") == 1 }
        observation.cancel()
        await observation.value
        try await wait { await references.base.subscriptionCount(for: "title") == 0 }

        await references.base.set("title", to: "Fresh")
        var fresh = runtime.run().makeAsyncIterator()
        await expectNext(&fresh, equals: .success("Fresh"))
        #expect(await references.openings == 2)
        #expect(await references.reads == 0)
    }

    private func wait(_ condition: @Sendable () async -> Bool) async throws {
        while !(await condition()) {
            try Task.checkCancellation()
            await Task.yield()
        }
    }
}

private struct EndedReferences: Compute.AsyncReferences {
    func value(for reference: JSON, context: [String: JSON]?) async throws -> JSON {
        "Snapshot"
    }
    func values(for reference: JSON, context: [String: JSON]?) -> AsyncStream<Result<
        JSON,
        JSONError
    >> {
        AsyncStream { $0.finish() }
    }
}

/// Models a document provider whose one-shot read takes the first stream value.
private actor StreamReferences: Compute.AsyncReferences {
    let base: TestReferences
    private(set) var reads = 0
    private(set) var openings = 0

    init(initiallyPending: Bool = false) {
        base = TestReferences(initiallyPending: initiallyPending)
    }

    func request(
        for reference: JSON,
        context: [String: JSON]?
    ) async throws -> Compute.Keyword.From {
        .init(reference: reference == "template_alias" ? "template" : reference, context: context)
    }

    func value(for reference: JSON, context: [String: JSON]?) async throws -> JSON {
        reads += 1
        var values = values(for: reference, context: context).makeAsyncIterator()
        guard let result = await values.next() else { throw CancellationError() }
        return try result.get()
    }

    nonisolated func values(for reference: JSON, context: [String: JSON]?) -> AsyncStream<Result<
        JSON,
        JSONError
    >> {
        AsyncStream { continuation in
            let task = Task {
                await opened()
                for await value in base.values(for: reference, context: context) {
                    guard !Task.isCancelled else { break }
                    continuation.yield(value)
                }
                continuation.finish()
            }
            continuation.onTermination = { @Sendable _ in task.cancel() }
        }
    }

    private func opened() {
        openings += 1
    }
}
