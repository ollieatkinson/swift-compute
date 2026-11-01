import Compute
import Testing

@Suite(.timeLimit(.minutes(1))) struct FrameScopeTests {
    @Test func concurrent_branch_scopes_inherit_context_and_preserve_explicit_and_canonical_bindings() async throws {
        let expression: JSON = [
            "inherited": .returns("from", ["reference": "template"]),
            "explicit": .returns("from", ["reference": "template", "context": ["user": "Explicit"]]),
            "native": .returns("from", ["reference": ["name": "template", "bindings": ["user": "Native"]]]),
            "item": .returns("item", []),
            "provider": .returns("scoped_provider", [:]),
        ]
        let entry: JSON = .returns("scoped_rows", [
            "bindings": [["user": "Dorothy"], ["user": "Witch", "region": .null]], "value": expression,
        ])
        let runtime = Compute.Runtime(document: .returns("from", [
            "reference": "entry", "context": ["user": "Parent", "region": "GB"],
        ]), functions: [ScopedRows(), ScopedProvider(), Compute.Keyword.From.Function(references: ScopedReferences(entry: entry))])
        defer { await runtime.cancel() }
        var values = runtime.run().makeAsyncIterator()
        #expect(try await values.next()?.get() == [
            ["inherited": ["user": "Dorothy", "region": "GB"], "explicit": ["user": "Explicit", "region": "GB"],
             "native": ["user": "Native", "region": "GB"], "item": 0, "provider": ["user": "Dorothy", "region": "GB"]],
            ["inherited": ["user": "Witch", "region": .null], "explicit": ["user": "Explicit", "region": .null],
             "native": ["user": "Native", "region": .null], "item": 1, "provider": ["user": "Witch", "region": .null]],
        ])
    }

    @Test func changing_branch_scope_replaces_live_dependencies_at_the_same_depth() async throws {
        let references = TestReferences()
        func rows(_ users: [String]) -> JSON {
            .returns("scoped_rows", ["bindings": .array(users.map { ["user": .string($0)] }),
                "value": .returns("from", ["reference": "name"])])
        }
        await references.set("rows", to: rows(["Dorothy", "Witch"]))
        await references.set(#"name?user="Dorothy""#, to: "Dorothy")
        await references.set(#"name?user="Witch""#, to: "Witch")
        let runtime = Compute.Runtime(document: .returns("from", ["reference": "rows"]),
            functions: [ScopedRows(), Compute.Keyword.From.Function(references: references)])
        defer { await runtime.cancel(); await references.finish() }
        var values = runtime.run().makeAsyncIterator()
        await expectNext(&values, equals: .success(["Dorothy", "Witch"]))
        await references.set(#"name?user="Witch""#, to: "Elphaba")
        await expectNext(&values, equals: .success(["Dorothy", "Elphaba"]))
        await references.set("rows", to: rows(["Witch"]))
        await expectNext(&values, equals: .success(["Elphaba"]))
        await references.fail(#"name?user="Dorothy""#, with: JSONError("Retired branch"))
        await references.set(#"name?user="Witch""#, to: "Current")
        await expectNext(&values, equals: .success(["Current"]))
    }

    @Test func scoped_canonical_references_still_report_cycles_instead_of_reaching_the_depth_limit() async throws {
        let entry: JSON = .returns("scoped_rows", ["bindings": [["user": "Dorothy"]],
            "value": .returns("from", ["reference": ["name": "loop", "bindings": ["user": "Witch"]]])])
        let runtime = Compute.Runtime(document: .returns("from", ["reference": "entry"]),
            functions: [ScopedRows(), Compute.Keyword.From.Function(references: ScopedReferences(entry: entry))])
        defer { await runtime.cancel() }
        await expectJSONError(containing: #"Reference cycle: entry {} -> loop {"user":"Witch"} -> loop {"user":"Witch"}"#) {
            _ = try await runtime.value()
        }
    }
}

private struct ScopedProvider: Compute.ReturnsKeywordDefinition {
    let name = "scoped_provider"
    func request(data: JSON, frame: Compute.Frame) async throws -> JSON { ["scope": .object(frame.scope ?? [:])] }
    func compute(data: JSON, frame: Compute.Frame) async throws -> JSON? {
        guard let scope = data.object?["scope"] else { throw JSONError("Request was not normalized") }
        return scope
    }
}

private struct ScopedRows: Compute.OpaqueOutputKeyword {
    let name = "scoped_rows"
    private struct Input: Decodable { let bindings: [[String: JSON]]; let value: JSON }
    func compute(data: JSON, frame: Compute.Frame) async throws -> JSON? {
        let input = try data.decode(Input.self)
        let scope = frame.scope
        let rows = try await withThrowingTaskGroup(of: (Int, JSON).self) { group in
            for (index, bindings) in input.bindings.enumerated() {
                group.addTask {
                    let branch = frame["rows", .index(index)].scoped(to: bindings)
                    #expect(branch.route.components == frame.route.components + [.key("rows"), .index(index)] && branch.depth == frame.depth)
                    let value = try await Computed<JSON>(rawValue: input.value, route: "value")
                        .compute(in: branch, item: .int(index))
                    return (index, value)
                }
            }
            var rows = [JSON](repeating: .null, count: input.bindings.count)
            for try await (index, value) in group { rows[index] = value }
            return rows
        }
        #expect(frame.scope == scope)
        return .array(rows)
    }
}

private struct ScopedReferences: Compute.References {
    let entry: JSON
    func request(for reference: JSON, context: [String: JSON]?) async throws -> Compute.Keyword.From {
        guard let name = reference.string ?? reference.object?["name"]?.string else { throw JSONError("Missing name") }
        return .init(reference: .string(name), context: (context ?? [:])
            .merging(reference.object?["bindings"]?.object ?? [:]) { _, explicit in explicit })
    }
    func value(for reference: JSON, context: [String: JSON]?) async throws -> JSON {
        switch reference.string {
        case "entry": entry
        case "template", "loop": .returns("from", ["reference": reference.string == "loop" ? "loop" : "label"])
        case "label": .object(context ?? [:])
        default: throw JSONError("Expected a canonical request")
        }
    }
}
