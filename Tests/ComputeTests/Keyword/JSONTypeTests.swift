import Compute
import Foundation
import Testing

@Suite struct JSONTypeTests {
    @Test(arguments: [
        ("null", JSON.null), ("boolean", .bool(true)), ("boolean", .bool(false)),
        ("number", .int(1)), ("number", .double(1)), ("number", .double(1.5)),
        ("string", .string("1")), ("array", .array([])), ("object", .object([:])),
        ("object", ["{returns}": ["unregistered_data": [:]]] as JSON),
        ("native", JSON(Date(timeIntervalSince1970: 0))),
    ])
    func computed_values_are_compared_by_structure_without_primitive_conversion(expected: String, input: JSON) async throws {
        for type in ["null", "boolean", "number", "string", "array", "object"] {
            try await expect(.returns("comparison", ["is": ["type": .string(type), "value": .returns("item", [])]]),
                in: Compute.Context(item: input), equals: .bool(type == expected))
        }
    }

    @Test func a_string_guard_short_circuits_a_coercing_regex_match() async throws {
        let predicate: JSON = .returns("yes", ["if": [
            .returns("comparison", ["is": ["type": "string", "value": .returns("item", [])]]),
            .returns("comparison", ["match": ["lhs": .returns("item", []), "rhs": "\\S"]]),
        ]])
        for input: JSON in [.null, 42, true, [], [:], "", " "] {
            try await expect(predicate, in: Compute.Context(item: input), equals: false)
        }
        try await expect(predicate, in: Compute.Context(item: "Dorothy"), equals: true)
        // Existing computed String conversions are independent of type guards.
        try await expect(.returns("comparison", ["match": ["lhs": 42, "rhs": "\\S"]]), equals: true)
    }

    @Test(arguments: [
        ["type": "unknown", "value": "text"] as JSON,
        ["type": "string"] as JSON, ["value": "text"] as JSON,
    ])
    func malformed_type_comparisons_report_an_error(input: JSON) async {
        await #expect(throws: (any Error).self) {
            try await value(.returns("comparison", ["is": input]))
        }
    }
}
