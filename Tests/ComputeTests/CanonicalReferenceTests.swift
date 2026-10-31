import Compute
import Testing

@Suite struct CanonicalReferenceTests {
    @Test func native_request_bindings_propagate_to_returned_references_after_normalization() async throws {
        let runtime = Compute.Runtime(document: .returns("from", [
            "reference": ["name": "template", "bindings": ["user": "Witch"]],
            "context": ["user": "Dorothy", "region": "GB"],
        ]), functions: [Compute.Keyword.From.Function(references: NativeReferences())])
        defer { await runtime.cancel() }
        #expect(try await runtime.value() == ["user": "Witch", "region": "GB"])
    }

    @Test func alias_requests_share_canonical_cycle_identity() async throws {
        let runtime = Compute.Runtime(document: .returns("from", [
            "reference": "loop", "context": ["user": "Witch"],
        ]), functions: [Compute.Keyword.From.Function(references: NativeReferences())])
        defer { await runtime.cancel() }
        await expectJSONError(containing: "Reference cycle: loop") { _ = try await runtime.value() }
    }
}

private struct NativeReferences: Compute.References {
    func request(for reference: JSON, context: [String: JSON]?) async throws -> Compute.Keyword.From {
        guard let name = reference.string ?? reference.object?["name"]?.string else { throw JSONError("Missing native name") }
        let bindings = reference.object?["bindings"]?.object ?? [:]
        return .init(reference: .string(name), context: (context ?? [:]).merging(bindings) { _, explicit in explicit })
    }

    func value(for reference: JSON, context: [String: JSON]?) async throws -> JSON {
        switch reference.string {
        case "template": .returns("from", ["reference": "label"])
        case "label": .object(context ?? [:])
        case "loop": .returns("from", ["reference": ["name": "loop", "bindings": ["user": "Witch"]]])
        default: throw JSONError("Expected a canonical request")
        }
    }
}
