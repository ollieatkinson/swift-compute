import Testing

@Suite(.serialized)
struct ArraySubscriptTests {

    @Test func reads_array_elements_and_handles_bounds() async throws {
        try await expect(["{returns}": ["array_subscript": ["of": ["a", "b", "c"], "index": 1]]], equals: "b")
        try await expect(["{returns}": ["array_subscript": ["of": ["a", "b", "c"], "index": 0, "reversed": true]]], equals: "c")
        try await expect(["{returns}": ["array_subscript": ["of": ["a"], "index": 2]]], equals: nil)
    }

    @Test func resolves_computed_inputs() async throws {
        try await expect([
            "{returns}": [
                "array_subscript": [
                    "of": ["{returns}": ["this": ["value": [1, 2, 3]]]],
                    "index": ["{returns}": ["this": ["value": 2]]],
                ],
            ],
        ], equals: 3)
    }
}
