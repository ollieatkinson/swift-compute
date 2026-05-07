import Testing

@Suite(.serialized)
struct ArraySliceTests {

    @Test func slices_clamps_and_reverses_arrays() async throws {
        try await expect(["{returns}": ["array_slice": ["of": [1, 2, 3, 4], "from": 1, "to": 3]]], equals: [2, 3])
        try await expect(["{returns}": ["array_slice": ["of": [1, 2, 3], "from": -10, "to": 10]]], equals: [1, 2, 3])
        try await expect(["{returns}": ["array_slice": ["of": [1, 2, 3], "from": 2, "to": 1]]], equals: [])
        try await expect(["{returns}": ["array_slice": ["of": [1, 2, 3], "to": 2, "reversed": true]]], equals: [3, 2])
        try await expect(["{returns}": ["array_slice": ["of": [], "from": 0, "to": 1]]], equals: [])
    }

    @Test func resolves_computed_bounds() async throws {
        try await expect([
            "{returns}": [
                "array_slice": [
                    "of": ["{returns}": ["this": ["value": ["a", "b", "c", "d"]]]],
                    "from": ["{returns}": ["this": ["value": 1]]],
                    "to": ["{returns}": ["this": ["value": 3]]],
                ],
            ],
        ], equals: ["b", "c"])
    }
}
