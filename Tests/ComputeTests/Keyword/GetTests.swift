import Compute
import Testing

@Suite(.timeLimit(.minutes(1))) struct GetTests {
    @Test func selects_keys_and_indices_from_a_computed_source() async throws {
        let source: JSON = .returns("this", ["value": ["0": "Key", "rows": [["name": "First"], ["name": "Last"]]]])
        try await expect(.returns("get", ["value": source, "path": ["rows", -1, "name"]]), equals: "Last")
        try await expect(.returns("get", ["value": source, "path": ["0"]]), equals: "Key")
        try await expect(.returns("get", ["value": source, "path": []]),
            equals: ["0": "Key", "rows": [["name": "First"], ["name": "Last"]]])
    }

    @Test(arguments: [JSON.null, JSON.string("text"), JSON.object([:]), JSON.array([])])
    func missing_paths_fail_instead_of_becoming_null(source: JSON) async throws {
        await expectJSONError(containing: "Missing value at name") {
            _ = try await value(.returns("get", ["value": source, "path": ["name"]]))
        }
    }

    @Test func explicit_null_is_preserved_and_invalid_indices_fail() async throws {
        try await expect(.returns("get", ["value": ["name": .null], "path": ["name"]]), equals: .null)
        await expectJSONError(containing: "Missing value at 1") {
            _ = try await value(.returns("get", ["value": ["Only"], "path": [1]]))
        }
    }

    @Test func selected_opaque_data_is_not_evaluated_a_second_time() async throws {
        let payload: JSON = .returns("error", ["message": "Deferred intent"])
        let runtime = Compute.Runtime(document: .returns("get", [
            "value": .returns("opaque_get_source", ["body": payload]), "path": ["body"],
        ]), functions: [OpaqueGetSource.function])
        defer { await runtime.cancel() }
        #expect(try await runtime.value() == payload)
    }

    @Test func source_failures_and_shape_changes_remain_recoverable() async throws {
        let references = TestReferences()
        await references.set("card", to: ["name": "Dorothy"])
        let runtime = try runtime(.returns("get", [
            "value": .returns("from", ["reference": "card"]), "path": ["name"],
        ]), references: references)
        defer { await runtime.cancel(); await references.finish() }
        var values = runtime.run().makeAsyncIterator()
        await expectNext(&values, equals: .success("Dorothy"))
        await references.set("card", to: [:])
        await expectNext(&values, equals: .failure(JSONError("Missing value", path: ["name"])))
        await references.set("card", to: ["name": .null])
        await expectNext(&values, equals: .success(.null))
        await references.fail("card", with: JSONError("Offline"))
        await expectNext(&values, equals: .failure(JSONError("Offline")))
        await references.set("card", to: ["name": "Restored"])
        await expectNext(&values, equals: .success("Restored"))
    }
}

private struct OpaqueGetSource: Compute.OpaqueOutputKeywordDefinition {
    static let name = "opaque_get_source"
    let body: JSON
    func compute(in frame: Compute.Frame) async throws -> JSON? { ["body": body] }
}
