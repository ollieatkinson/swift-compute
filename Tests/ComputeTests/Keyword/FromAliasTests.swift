import Compute
import Testing

@Suite(.timeLimit(.minutes(1)))
struct FromAliasTests {
    @Test func a_named_provider_shares_source_interest_across_depths_and_stays_live() async throws {
        let references = TestReferences()
        await references.set("feature", to: true)
        let lookup: JSON = .returns("lookup", ["reference": "feature"])
        let runtime = Compute.Runtime(document: ["one": lookup, "two": [["nested": lookup]]],
                                      functions: [Compute.Keyword.From.Function(references: references, name: "lookup")])
        defer { await runtime.cancel() }
        var changes = runtime.run().makeAsyncIterator()
        await expectNext(&changes, equals: .success(["one": true, "two": [["nested": true]]]))
        #expect(await references.subscriptionCount(for: "feature") == 1)
        await references.set("feature", to: false)
        await expectNext(&changes, equals: .success(["one": false, "two": [["nested": false]]]))
        #expect(await references.subscriptionCount(for: "feature") == 1)
        await runtime.cancel()
        #expect(await changes.next() == nil)
        while await references.subscriptionCount(for: "feature") != 0 {
            try Task.checkCancellation()
            await Task.yield()
        }
    }

    @Test func distinct_named_providers_can_resolve_the_same_reference_in_one_chain() async throws {
        let primary = TestReferences()
        let other = TestReferences()
        await primary.set("same", to: .returns("lookup", ["reference": "same"]))
        await other.set("same", to: "Other provider")
        let runtime = Compute.Runtime(document: .returns("from", ["reference": "same"]),
                                      functions: [
                                          Compute.Keyword.From.Function(references: primary),
                                          Compute.Keyword.From.Function(references: other, name: "lookup"),
                                      ])
        defer { await runtime.cancel() }
        #expect(try await runtime.value() == "Other provider")
    }

    @Test func a_cycle_within_a_named_provider_is_still_rejected() async throws {
        let references = TestReferences()
        await references.set("same", to: .returns("lookup", ["reference": "same"]))
        let runtime = Compute.Runtime(document: .returns("lookup", ["reference": "same"]),
                                      functions: [Compute.Keyword.From.Function(references: references, name: "lookup")])
        defer { await runtime.cancel() }
        do {
            _ = try await runtime.value()
            Issue.record("A named reference cycle was accepted")
        } catch let error as JSONError {
            #expect(error.message.contains("Reference cycle"))
        }
    }

    @Test(arguments: [false, true])
    func applying_a_quoted_program_keeps_parameters_ancestry_and_depth(cyclic: Bool) async throws {
        let references = TestReferences()
        await references.set("template", to: "A cycle must not read this")
        let program: JSON = cyclic
            ? .returns("lookup", ["reference": "template"])
            : .returns("item", ["title"])
        let runtime = Compute.Runtime(document: .returns("apply_program", ["program": program]),
                                      context: .init(item: ["title": "Outer"]),
                                      functions: [
                                          Compute.Keyword.From.Function(references: references, name: "lookup"),
                                          ApplyProgram(),
                                      ])
        defer { await runtime.cancel() }
        if cyclic {
            do {
                _ = try await runtime.value()
                Issue.record("A separately applied program lost its reference ancestry")
            } catch let error as JSONError {
                #expect(error.message.contains("Reference cycle"))
            }
        } else {
            #expect(try await runtime.value() == [
                "value": "Entered", "outer": "Outer", "depth": 1,
            ])
        }
    }
}

private struct ApplyProgram: Compute.OpaqueOutputKeyword {
    var name: String {
        "apply_program"
    }

    func compute(data: JSON, frame: Compute.Frame) async throws -> JSON? {
        let entered = try await frame.following(.init(reference: "template"),
                                                using: "lookup", item: ["title": "Entered"])
        return try await [
            "value": entered.compute(data["program"]),
            "outer": frame.context.item?["title"] ?? .null,
            "depth": .int(entered.depth - frame.depth),
        ]
    }
}
