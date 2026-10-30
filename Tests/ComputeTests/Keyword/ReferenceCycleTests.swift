import Compute
import Testing

@Suite(.timeLimit(.minutes(1))) struct ReferenceCycleTests {
    @Test(arguments: [false, true], [false, true])
    func recursive_templates_can_advance_through_local_items(live: Bool, withDefault: Bool) async throws {
        let walk: JSON = .returns("from", ["reference": "walk"],
            default: withDefault ? "Premature fallback" : nil)
        let template: JSON = .returns("either", [
            [
                "condition": .returns("exists", ["value": .returns("item", ["child"])]),
                "value": .returns("map", ["src": .returns("item", ["child"]), "dst": walk]),
            ],
            ["value": .returns("item", ["name"])],
        ])
        let references = TestReferences()
        await references.set("walk", to: template)
        let function: any AnyReturnsKeyword
        if live {
            function = Compute.Keyword.From.Function(references: references)
        } else {
            function = Compute.Keyword.From.Function(references: FixedReferences(values: ["walk": template]))
        }
        let runtime = Compute.Runtime(document: walk,
            context: Compute.Context(item: ["child": ["child": ["name": "Leaf"]]]),
            functions: [function])
        defer { await runtime.cancel(); await references.finish() }
        #expect(try await runtime.value() == "Leaf")
    }

    @Test func revisiting_a_reference_and_local_item_still_reports_a_cycle() async throws {
        let references = FixedReferences(values: [
            "first": .returns("map", ["src": ["step": "child"],
                "dst": .returns("from", ["reference": "second"])]),
            "second": .returns("map", ["src": ["step": "start"],
                "dst": .returns("from", ["reference": "first"])]),
        ])
        let runtime = Compute.Runtime(document: .returns("from", ["reference": "first"]),
            context: Compute.Context(item: ["step": "start"]),
            functions: [Compute.Keyword.From.Function(references: references)])
        defer { await runtime.cancel() }
        await expectJSONError(containing: "Reference cycle: first -> second -> first") {
            _ = try await runtime.value()
        }
    }

    @Test func synchronous_references_name_the_full_resolution_chain() async throws {
        let references = FixedReferences(values: [
            "entry": .returns("from", ["reference": "first"]),
            "first": .returns("from", ["reference": "second"]),
            "second": .returns("from", ["reference": "first"]),
        ])
        let runtime = Compute.Runtime(document: .returns("from", ["reference": "entry"]), functions: [
            Compute.Keyword.From.Function(references: references),
        ])
        defer { await runtime.cancel() }
        await expectJSONError(containing: "Reference cycle: entry -> first -> second -> first") {
            _ = try await runtime.value()
        }
    }

    @Test func live_reference_cycles_recover_and_replace_dependencies() async throws {
        let references = TestReferences()
        await references.set("first", to: .returns("from", ["reference": "second"]))
        await references.set("second", to: .returns("from", ["reference": "first"]))
        await references.set("third", to: "Red")
        let runtime = try runtime(.returns("from", ["reference": "first"]), references: references)
        defer { await runtime.cancel(); await references.finish() }
        var values = runtime.run().makeAsyncIterator()
        if case .failure(let error) = await values.next() {
            #expect(error.message == "Reference cycle: first -> second -> first")
        } else { Issue.record("Expected a named reference cycle") }
        await references.set("second", to: "Blue")
        await expectNext(&values, equals: .success("Blue"))
        await references.set("first", to: .returns("from", ["reference": "third"]))
        await expectNext(&values, equals: .success("Red"))
        await references.fail("second", with: JSONError("Retired source"))
        await references.set("third", to: "Green")
        await expectNext(&values, equals: .success("Green"))
    }

    @Test func context_is_part_of_reference_identity_and_the_cycle_diagnostic() async throws {
        let references = TestReferences()
        let one: JSON = .returns("from", ["reference": "card", "context": ["programme": "p1"]])
        let two: JSON = .returns("from", ["reference": "card", "context": ["programme": "p2"]])
        await references.set("card?programme=\"p1\"", to: two)
        await references.set("card?programme=\"p2\"", to: "Distinct entity")
        let runtime = try runtime(one, references: references)
        defer { await runtime.cancel(); await references.finish() }
        var values = runtime.run().makeAsyncIterator()
        await expectNext(&values, equals: .success("Distinct entity"))
        await references.set("card?programme=\"p2\"", to: one)
        if case .failure(let error) = await values.next() {
            #expect(error.message == "Reference cycle: card {\"programme\":\"p1\"} -> card {\"programme\":\"p2\"} -> card {\"programme\":\"p1\"}")
        } else { Issue.record("Expected a contextual cycle") }
    }

    @Test func sibling_branches_can_resolve_the_same_reference() async throws {
        let shared: JSON = .returns("from", ["reference": "shared"])
        let references = FixedReferences(values: [
            "root": ["left": shared, "right": shared, "rows": [shared, shared]], "shared": "Dorothy",
        ])
        let runtime = Compute.Runtime(document: .returns("from", ["reference": "root"]), functions: [
            Compute.Keyword.From.Function(references: references),
        ])
        defer { await runtime.cancel() }
        #expect(try await runtime.value() == ["left": "Dorothy", "right": "Dorothy", "rows": ["Dorothy", "Dorothy"]])
    }

    @Test(arguments: [
        JSON.returns("get", ["value": .returns("this", ["value": .returns("from", ["reference": "root"])]), "path": []]),
        JSON.returns("frame_forward", .returns("from", ["reference": "root"])),
    ])
    func reference_ancestry_survives_computed_properties_and_custom_frame_projection(wrapper: JSON) async throws {
        let references = FixedReferences(values: ["root": wrapper])
        let runtime = Compute.Runtime(document: .returns("from", ["reference": "root"]), functions: [
            Compute.Keyword.From.Function(references: references), FrameForward(),
        ])
        defer { await runtime.cancel() }
        await expectJSONError(containing: "Reference cycle: root -> root") {
            _ = try await runtime.value()
        }
    }

    @Test func a_default_can_break_a_reference_cycle_and_remain_live() async throws {
        let references = TestReferences()
        await references.set("root", to: .returns("from", ["reference": "root"], default: "Fallback"))
        let runtime = try runtime(.returns("from", ["reference": "root"]), references: references)
        defer { await runtime.cancel(); await references.finish() }
        var values = runtime.run().makeAsyncIterator()
        await expectNext(&values, equals: .success("Fallback"))
        await references.set("root", to: "Restored")
        await expectNext(&values, equals: .success("Restored"))
    }
}

private struct FixedReferences: Compute.References {
    let values: [String: JSON]
    func value(for reference: JSON, context: [String: JSON]?) async throws -> JSON {
        guard let key = reference.string, let value = values[key] else {
            throw Compute.Error.unresolvedReference(reference)
        }
        return value
    }
}

private struct FrameForward: AnyReturnsKeyword {
    let name = "frame_forward"
    func compute(data: JSON, frame: Compute.Frame) async throws -> JSON? {
        try await frame["forwarded"].compute(data)
    }
}
