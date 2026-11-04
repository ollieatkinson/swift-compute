import Compute
import Testing

@Suite(.timeLimit(.minutes(1)))
struct ComputeRuntimeRouteTests {
    @Test
    func observing_a_field_keeps_unrelated_fields_inert() async throws {
        let runtime = Compute.Runtime(document: [
            "profile": [
                "name": .returns("literal", ["value": "Dorothy"]),
                "unused": .returns("error", ["message": "Unrequested field"])
            ]
        ])
        defer { await runtime.cancel() }
        var names = runtime.run(at: ["profile", "name"]).makeAsyncIterator()
        let name = await names.next()
        #expect(name == .success("Dorothy"))
    }

    @Test
    func an_observed_field_failure_does_not_replace_an_independent_fields_value() async throws {
        let runtime = Compute.Runtime(document: [
            "name": .returns("literal", ["value": "Dorothy"]),
            "broken": .returns("error", ["message": "Broken field"])
        ])
        defer { await runtime.cancel() }
        var names = runtime.run(at: ["name"]).makeAsyncIterator()
        var errors = runtime.run(at: ["broken"]).makeAsyncIterator()
        let name = await names.next()
        #expect(name == .success("Dorothy"))
        #expect(await errors.next() == .failure(JSONError("Broken field")))
    }

    @Test
    func live_fields_recover_independently_while_a_whole_document_reports_the_failure(
    ) async throws {
        let references = TestReferences()
        await references.set("name", to: "Dorothy")
        await references.fail("status", with: JSONError("Unavailable"))
        let runtime = try runtime([
            "name": .returns("from", ["reference": "name"]),
            "status": .returns("from", ["reference": "status"])
        ], references: references)
        defer { await runtime.cancel() }
        var names = runtime.run(at: ["name"]).makeAsyncIterator()
        var statuses = runtime.run(at: ["status"]).makeAsyncIterator()
        var documents = runtime.run().makeAsyncIterator()
        await expectNext(&names, equals: .success("Dorothy"))
        await expectNext(&statuses, equals: .failure(JSONError("Unavailable")))
        await expectNext(&documents, equals: .failure(JSONError("Unavailable")))
        await references.set("name", to: "Elphaba")
        await expectNext(&names, equals: .success("Elphaba"))
        await references.set("status", to: "Ready")
        await expectNext(&statuses, equals: .success("Ready"))
        await expectNext(&documents, equals: .success(["name": "Elphaba", "status": "Ready"]))
        await runtime.cancel()
        #expect(await names.next() == nil)
        #expect(await statuses.next() == nil)
        #expect(await documents.next() == nil)
    }

    @Test
    func removing_a_route_releases_its_pending_source_without_stopping_another_route() async throws {
        let references = TestReferences(initiallyPending: true)
        await references.set("name", to: "Dorothy")
        let runtime = try runtime([
            "name": .returns("from", ["reference": "name"]),
            "hidden": .returns("from", ["reference": "hidden"])
        ], references: references)
        defer { await runtime.cancel() }
        var names = runtime.run(at: ["name"]).makeAsyncIterator()
        await expectNext(&names, equals: .success("Dorothy"))
        #expect(await references.subscriptionCount(for: "hidden") == 0)
        let hidden = Task { for await _ in runtime.run(at: ["hidden"]) {} }
        defer { hidden.cancel() }
        try await wait { await references.subscriptionCount(for: "hidden") == 1 }
        hidden.cancel()
        await hidden.value
        try await wait { await references.subscriptionCount(for: "hidden") == 0 }
        #expect(await references.subscriptionCount(for: "name") == 1)
        await references.set("name", to: "Elphaba")
        await expectNext(&names, equals: .success("Elphaba"))
    }

    @Test(arguments: [false, true])
    func whole_document_reads_and_steps_keep_their_failure_contract_after_a_field_subscription(
        stepping: Bool
    ) async throws {
        let references = TestReferences()
        await references.set("name", to: "Dorothy")
        let runtime = try runtime([
            "name": .returns("from", ["reference": "name"]),
            "broken": .returns("error", ["message": "Broken field"])
        ], references: references)
        defer { await runtime.cancel() }
        var names = runtime.run(at: ["name"]).makeAsyncIterator()
        await expectNext(&names, equals: .success("Dorothy"))
        do {
            if stepping { _ = try await runtime.step() }
            else { _ = try await runtime.value() }
            Issue.record("A whole-document read must still evaluate its broken field")
        } catch { #expect(JSONError(error) == JSONError("Broken field")) }
        await references.set("name", to: "Elphaba")
        await expectNext(&names, equals: .success("Elphaba"))
    }

    @Test
    func array_routes_select_only_their_requested_element() async throws {
        let runtime = Compute.Runtime(document: [
            "cards": [
                .returns("literal", ["value": "Dorothy"]),
                .returns("error", ["message": "Unrequested card"])
            ]
        ])
        defer { await runtime.cancel() }
        var cards = runtime.run(at: ["cards", .index(0)]).makeAsyncIterator()
        #expect(await cards.next() == .success("Dorothy"))
    }

    @Test
    func negative_array_routes_share_live_inputs_and_release_only_their_subscription() async throws {
        let references = TestReferences(initiallyPending: true)
        await references.set("title", to: "Dorothy")
        let runtime = try runtime([
            "cards": [
                .returns("error", ["message": "Unrequested card"]),
                ["titles": [.returns("from", ["reference": "title"])]]
            ]
        ], references: references)
        defer { await runtime.cancel() }
        let route: Compute.Route = ["cards", .index(-1), "titles", .index(-1)]
        let negative = Task {
            for await result in runtime.run(at: route) {
                #expect(result == .success("Dorothy"))
            }
        }
        defer { negative.cancel() }
        try await wait { await references.subscriptionCount(for: "title") == 1 }
        var positive = runtime.run(at: ["cards", .index(1), "titles", .index(0)]).makeAsyncIterator()
        await expectNext(&positive, equals: .success("Dorothy"))
        negative.cancel()
        await negative.value
        await references.set("title", to: "Elphaba")
        await expectNext(&positive, equals: .success("Elphaba"))
        #expect(await references.subscriptionCount(for: "title") == 1)
        var resumed = runtime.run(at: route).makeAsyncIterator()
        await expectNext(&resumed, equals: .success("Elphaba"))
        await references.fail("title", with: JSONError("Unavailable"))
        await expectNext(&resumed, equals: .failure(JSONError("Unavailable")))
        await references.set("title", to: "Recovered")
        await expectNext(&resumed, equals: .success("Recovered"))
        await runtime.cancel()
        try await wait { await references.subscriptionCount(for: "title") == 0 }
    }

    @Test
    func negative_indices_inside_computed_output_follow_the_current_array_length() async throws {
        let references = TestReferences()
        await references.set("cards", to: ["Dorothy", "Elphaba"])
        let runtime = try runtime(.returns("from", ["reference": "cards"]), references: references)
        defer { await runtime.cancel() }
        var values = runtime.run(at: [.index(-1)]).makeAsyncIterator()
        await expectNext(&values, equals: .success("Elphaba"))
        await references.set("cards", to: ["Glinda"])
        await expectNext(&values, equals: .success("Glinda"))
    }

    @Test
    func a_negative_array_route_publishes_while_an_unrelated_input_is_pending() async throws {
        let references = TestReferences(initiallyPending: true)
        await references.set("title", to: "Dorothy")
        let runtime = try runtime([
            "waiting": .returns("from", ["reference": "waiting"]),
            "cards": [.returns("from", ["reference": "title"])]
        ], references: references)
        defer { await runtime.cancel() }
        var documents = runtime.run().makeAsyncIterator()
        try await wait { await references.subscriptionCount(for: "waiting") == 1 }
        var cards = runtime.run(at: ["cards", .index(-1)]).makeAsyncIterator()
        await expectNext(&cards, equals: .success("Dorothy"))
        await references.set("title", to: "Elphaba")
        await expectNext(&cards, equals: .success("Elphaba"))
        await references.set("waiting", to: "Ready")
        await expectNext(&documents, equals: .success(["waiting": "Ready", "cards": ["Elphaba"]]))
    }

    @Test
    func a_computed_ancestor_keeps_its_opaque_output_boundary() async throws {
        let deferred = JSON.returns("error", ["message": "Deferred data"])
        let runtime = Compute.Runtime(document: [
            "card": .returns("literal", ["value": ["title": deferred]])
        ])
        defer { await runtime.cancel() }
        var titles = runtime.run(at: ["card", "title"]).makeAsyncIterator()
        #expect(await titles.next() == .success(deferred))
    }

    @Test
    func an_evaluated_opaque_program_is_settled_data() async throws {
        let deferred = JSON.returns("error", ["message": "Deferred data"])
        let runtime = Compute.Runtime(document: [
            "title": .returns("literal", ["value": deferred])
        ])
        defer { await runtime.cancel() }
        #expect(try await runtime.value(at: ["title"]) == deferred)
        let remaining = await runtime.remainingThoughtCount
        try #require(remaining == 0)
        var titles = runtime.run(at: ["title"]).makeAsyncIterator()
        #expect(await titles.next() == .success(deferred))
    }

    @Test(arguments: [false, true])
    func a_field_progresses_while_the_document_waits_for_another_input(compiled: Bool) async throws {
        let references = TestReferences(initiallyPending: true)
        await references.set("name", to: "Dorothy")
        let runtime = try runtime([
            "a_waiting": .returns("from", ["reference": "waiting"]),
            "z_name": compiled ? .returns("from", ["reference": "name"]) : "Dorothy"
        ], references: references)
        defer { await runtime.cancel() }
        var documents = runtime.run().makeAsyncIterator()
        try await wait { await references.subscriptionCount(for: "waiting") == 1 }
        // Bound the regression without leaving its pending root task behind.
        let fallback = Task {
            do { try await Task.sleep(nanoseconds: 3_000_000_000) }
            catch { return }
            await references.set("waiting", to: "Ready")
        }
        defer { fallback.cancel() }
        var names = runtime.run(at: ["z_name"]).makeAsyncIterator()
        await expectNext(&names, equals: .success("Dorothy"))
        #expect((try? await references.value(for: "waiting", context: nil)) == nil)
        if compiled {
            await references.set("name", to: "Elphaba")
            await expectNext(&names, equals: .success("Elphaba"))
            #expect((try? await references.value(for: "waiting", context: nil)) == nil)
        }
        fallback.cancel()
        await references.set("waiting", to: "Ready")
        await expectNext(&documents, equals: .success([
            "a_waiting": "Ready",
            "z_name": compiled ? "Elphaba" : "Dorothy"
        ]))
        await runtime.cancel()
        #expect(await documents.next() == nil)
        #expect(await names.next() == nil)
    }

    @Test
    func overlapping_whole_reads_and_route_setup_do_not_publish_internal_cancellation(
    ) async throws {
        // Overlap ordinary reads and route registration to exercise both gate
        // orders, including a one-shot read overtaking a queued live wave.
        try await withThrowingTaskGroup(of: Void.self) { group in
            for _ in 0 ..< 32 {
                group.addTask {
                    let references = TestReferences()
                    await references.set("minimum", to: 36)
                    let runtime = Compute.Runtime(
                        document: ["profile": [
                            "adult": .returns("comparison", ["greater_or_equal": [
                                "lhs": .returns("item", ["age"]),
                                "rhs": .returns("from", ["reference": "minimum"])
                            ]]),
                            "name": .returns("item", ["name"])
                        ]],
                        context: Compute.Context(item: users[2]),
                        functions: [Compute.Keyword.From.Function(references: references)]
                    )
                    defer { await runtime.cancel() }
                    var adults = runtime.run(at: ["profile", "adult"]).makeAsyncIterator()
                    try #require(try await runtime.value(at: ["profile", "name"]) == "Ste")
                    try #require(await adults.next() == .success(true))
                    await references.set("minimum", to: 40)
                    try #require(await adults.next() == .success(false))
                }
            }
            try await group.waitForAll()
        }
    }

    private func wait(_ condition: @Sendable () async -> Bool) async throws {
        while !(await condition()) {
            try Task.checkCancellation()
            await Task.yield()
        }
    }
}
