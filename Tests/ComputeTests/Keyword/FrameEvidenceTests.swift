import Compute
import _JSON
import Testing

@Suite struct FrameEvidenceTests {
    @Test func custom_evidence_is_captured_with_its_value_and_remains_unevaluated() async throws {
        let runtime = Compute.Runtime(document: .returns("explain", ["value": .returns("audited_value", ["value": "Blue"])]),
            functions: [AuditedValue()])
        defer { await runtime.cancel() }
        let result = try await runtime.value()
        #expect(result.object?["value"] == "Blue")
        let evidence = try #require(result.object?["thoughts"]?.array?.first { $0.object?["keyword"] == "selection" })
        #expect(evidence.object?["output"] == "Blue")
        #expect(evidence.object?["input"] == .returns("error", ["message": "Authored evidence must stay data"]))
    }

    @Test func recording_preserves_normal_output_and_is_owned_by_each_runtime() async throws {
        let first = Compute.Runtime(document: .returns("audited_value", ["value": "Dorothy"]), functions: [AuditedValue()])
        let second = Compute.Runtime(document: .returns("audited_value", ["value": "Witch"]), functions: [AuditedValue()])
        defer { await first.cancel(); await second.cancel() }
        async let firstValue = first.value()
        async let secondValue = second.value()
        #expect(try await firstValue == "Dorothy")
        #expect(try await secondValue == "Witch")
        #expect(await first.thoughts.first { $0.keyword == "selection" }?.output == "Dorothy")
        #expect(await second.thoughts.first { $0.keyword == "selection" }?.output == "Witch")
    }

    @Test func explained_failures_preserve_structured_error_paths() async throws {
        let runtime = Compute.Runtime(document: .returns("explain", ["value": .returns("failed_value", [:])]),
            functions: [FailedValue()])
        defer { await runtime.cancel() }
        let result = try await runtime.value()
        #expect(result.object?["error"] == "Unavailable at profile.name")
        let failure = try #require(result.object?["failure"])
        #expect(try failure.decode(JSONError.self) == JSONError("Unavailable", path: ["profile", "name"]))
    }
}

private struct FailedValue: AnyReturnsKeyword {
    var name: String { "failed_value" }
    func compute(data: JSON, frame: Compute.Frame) async throws -> JSON? {
        throw JSONError("Unavailable", path: ["profile", "name"])
    }
}

private struct AuditedValue: AnyReturnsKeyword {
    var name: String { "audited_value" }
    func compute(data: JSON, frame: Compute.Frame) async throws -> JSON? {
        let value = data.object?["value"] ?? .null
        await frame.record(Compute.Thought(route: frame.route, depth: frame.depth, keyword: "selection",
            input: .returns("error", ["message": "Authored evidence must stay data"]), output: value))
        return value
    }
}
