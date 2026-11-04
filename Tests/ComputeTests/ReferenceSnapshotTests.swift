import Compute
import Testing

@Suite(.timeLimit(.minutes(1)))
struct ReferenceSnapshotTests {
    @Test
    func reference_provenance_is_inert_and_does_not_make_returned_fields_atomic() async throws {
        let references = TestReferences()
        let evidence = Compute.Thought(
            route: ["provider"],
            depth: 0,
            keyword: "provenance",
            input: .returns("error", ["message": "Inert metadata"]),
            output: "A"
        )
        await references.set("definition", to: JSON(Compute.ReferenceSnapshot.value([
            "score": .returns("from", ["reference": "score"]),
            "unused": .returns("error", ["message": "Unrequested sibling"])
        ], thoughts: [evidence])))
        await references.set("score", to: 1)
        let runtime = makeRuntime(references)
        defer { await runtime.cancel() }
        var scores = runtime.run(at: ["score"], tracing: true).makeAsyncIterator()
        let first = try #require(await scores.next())
        #expect(first.result == .success(1))
        #expect(first.thoughts.contains(evidence))
        await references.set("score", to: 2)
        let second = try #require(await scores.next())
        #expect(second.result == .success(2) && second.thoughts.contains(evidence))
        #expect(await references.subscriptionCount(for: "score") == 1)
    }

    @Test
    func provider_failure_and_program_failure_keep_their_provenance_and_recover() async throws {
        let references = TestReferences()
        let marker = Compute.Thought(route: [], depth: 0, keyword: "provider", output: "Evidence")
        let error = JSONError("Unavailable", path: ["upstream", "value"])
        await references.set(
            "definition",
            to: JSON(Compute.ReferenceSnapshot.failure(error, thoughts: [marker]))
        )
        let runtime = makeRuntime(references)
        defer { await runtime.cancel() }
        var values = runtime.run(tracing: true).makeAsyncIterator()
        let failed = try #require(await values.next())
        #expect(failed.result == .failure(error) && failed.thoughts.contains(marker))
        await references.set("definition", to: JSON(Compute.ReferenceSnapshot.value(
            .returns("error", ["message": "Program failed"]),
            thoughts: [marker]
        )))
        let program = try #require(await values.next())
        #expect(program.result == .failure(JSONError("Program failed")) && program.thoughts
            .contains(marker))
        await references.set(
            "definition",
            to: JSON(Compute.ReferenceSnapshot.value(.null, thoughts: [marker]))
        )
        let recovered = try #require(await values.next())
        #expect(recovered.result == .success(.null) && recovered.thoughts.contains(marker))
    }

    @Test(arguments: [8, 24], [false, true])
    func provenance_does_not_consume_program_depth(length: Int, recorded: Bool) async throws {
        let references = TestReferences()
        for index in 0 ..< length {
            let value: JSON = index == length - 1 ? "Ready" : .returns(
                "from",
                ["reference": .string("ref\(index + 1)")]
            )
            await references.set(
                "ref\(index)",
                to: recorded ? JSON(Compute.ReferenceSnapshot.value(value)) : value
            )
        }
        let runtime = Compute.Runtime(
            document: .returns("from", ["reference": "ref0"]),
            functions: [Compute.Keyword.From
                .Function(references: references)]
        )
        defer { await runtime.cancel() }
        if length == 8 { #expect(try await runtime.value() == "Ready") }
        else {
            await #expect(throws: JSONError(Compute.Error.recursionLimitExceeded)) {
                try await runtime.value()
            }
        }
    }

    @Test
    func reference_cycles_and_defaults_keep_native_semantics() async throws {
        let references = TestReferences()
        await references.set("definition", to: JSON(Compute.ReferenceSnapshot.value(
            .returns("from", ["reference": "definition"])
        )))
        let runtime = makeRuntime(references)
        defer { await runtime.cancel() }
        var values = runtime.run(tracing: true).makeAsyncIterator()
        let cycle = try #require(await values.next())
        #expect(cycle.result == .failure(JSONError(
            "Reference cycle: definition -> definition",
            path: ["{returns}", "from"]
        )))
        await references.set("definition", to: JSON(Compute.ReferenceSnapshot.value(
            .returns("error", ["message": "Choose fallback"], default: ["score": 7])
        )))
        #expect(await values.next()?.result == .success(["score": 7]))
    }

    @Test
    func opaque_outputs_and_encoded_lookalikes_are_not_transport_snapshots() async throws {
        let marker = Compute.Thought(route: [], depth: 0, keyword: "not_transport", output: 1)
        let packet = Compute.ReferenceSnapshot.value(7, thoughts: [marker])
        let literal = Compute.Runtime(
            document: .returns("opaque_packet", [:]),
            functions: [OpaquePacket(value: JSON(packet))]
        )
        defer { await literal.cancel() }
        #expect(try await literal.value() == JSON(packet))
        let encoded = try JSON.encoded(packet)
        let references = TestReferences()
        await references.set("definition", to: encoded)
        let runtime = makeRuntime(references)
        defer { await runtime.cancel() }
        var outputs = runtime.run(tracing: true).makeAsyncIterator()
        let output = try #require(await outputs.next())
        #expect(output.result == .success(encoded))
        #expect(!output.thoughts.contains(marker))
    }

    @Test
    func metadata_changes_do_not_replay_equal_plain_values() async throws {
        let references = TestReferences()
        func packet(_ value: JSON, _ marker: JSON) -> JSON {
            JSON(Compute.ReferenceSnapshot.value(["score": value], thoughts: [
                Compute.Thought(route: [], depth: 0, keyword: "source", output: marker)
            ]))
        }
        await references.set("definition", to: packet(1, "A"))
        let runtime = makeRuntime(references)
        defer { await runtime.cancel() }
        var traced = runtime.run(at: ["score"], tracing: true).makeAsyncIterator()
        var plain = runtime.run(at: ["score"]).makeAsyncIterator()
        try #require(await traced.next()?.result == .success(1))
        try #require(await plain.next() == .success(1))
        await references.set("definition", to: packet(1, "B"))
        let changed = try #require(await traced.next())
        #expect(changed.result == .success(1))
        #expect(changed.thoughts.contains { $0.keyword == "source" && $0.output == "B" })
        await references.set("definition", to: packet(2, "B"))
        try #require(await traced.next()?.result == .success(2))
        try #require(await plain.next() == .success(2))
    }

    private func makeRuntime(_ references: TestReferences) -> Compute.Runtime {
        Compute.Runtime(
            document: .returns("from", ["reference": "definition"]),
            functions: [Compute.Keyword.From.Function(references: references)]
        )
    }
}

private struct OpaquePacket: Compute.OpaqueOutputKeyword {
    let name = "opaque_packet"
    let value: JSON
    func compute(data: JSON, frame: Compute.Frame) async throws -> JSON? {
        value
    }
}
