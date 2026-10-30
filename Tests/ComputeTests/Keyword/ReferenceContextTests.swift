import Compute
import Testing

@Suite(.timeLimit(.minutes(1))) struct ReferenceContextTests {
    @Test func context_preserves_explicit_json_null() async throws {
        let references = TestReferences()
        await references.set("name?user=null", to: "Present null")
        let runtime = try runtime(.returns("from", ["reference": "name", "context": ["user": .null]]), references: references)
        defer { await runtime.cancel(); await references.finish() }
        #expect(try await runtime.value() == "Present null")
    }

    @Test func returned_references_inherit_context_and_explicit_bindings_override_it() async throws {
        let references = TestReferences()
        await references.set("template?user=\"Dorothy\"", to: [
            "inherited": .returns("from", ["reference": "name"]),
            "explicit": .returns("from", ["reference": "name", "context": ["user": "Witch"]]),
        ])
        await references.set("name?user=\"Dorothy\"", to: "Dorothy")
        await references.set("name?user=\"Witch\"", to: "Witch")
        let runtime = try runtime(.returns("from", ["reference": "template", "context": ["user": "Dorothy"]]), references: references)
        defer { await runtime.cancel(); await references.finish() }
        #expect(try await runtime.value() == ["inherited": "Dorothy", "explicit": "Witch"])
    }

    @Test func sibling_templates_keep_distinct_live_dependency_keys_at_the_same_depth() async throws {
        let references = TestReferences()
        let template: JSON = ["name": .returns("from", ["reference": "name", "context": [:]])]
        await references.set("template?user=\"Dorothy\"", to: template)
        await references.set("template?user=\"Witch\"", to: template)
        await references.set("name?user=\"Dorothy\"", to: "Dorothy")
        await references.set("name?user=\"Witch\"", to: "Witch")
        let runtime = try runtime([
            "left": .returns("from", ["reference": "template", "context": ["user": "Dorothy"]]),
            "right": .returns("from", ["reference": "template", "context": ["user": "Witch"]]),
        ], references: references)
        defer { await runtime.cancel(); await references.finish() }
        var values = runtime.run().makeAsyncIterator()
        await expectNext(&values, equals: .success(["left": ["name": "Dorothy"], "right": ["name": "Witch"]]))
        await references.set("name?user=\"Witch\"", to: "Elphaba")
        await expectNext(&values, equals: .success(["left": ["name": "Dorothy"], "right": ["name": "Elphaba"]]))
    }

    @Test func cycle_diagnostics_use_effective_inherited_bindings() async throws {
        let references = TestReferences()
        await references.set("root?user=\"Dorothy\"", to: .returns("from", ["reference": "root"]))
        let runtime = try runtime(.returns("from", ["reference": "root", "context": ["user": "Dorothy"]]), references: references)
        defer { await runtime.cancel(); await references.finish() }
        await expectJSONError(containing: "Reference cycle: root {\"user\":\"Dorothy\"} -> root {\"user\":\"Dorothy\"}") {
            _ = try await runtime.value()
        }
    }
}
