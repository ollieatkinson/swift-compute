import Testing

@Suite(.serialized)
struct ArrayZipTests {

    @Test func zips_to_shortest_array_and_can_flatten() async throws {
        try await expect(["{returns}": ["array_zip": ["together": [[1, 2, 3], ["a", "b"]]]]], equals: [[1, "a"], [2, "b"]])
        try await expect(["{returns}": ["array_zip": ["together": [[1, 2], ["a", "b"]], "flattened": true]]], equals: [1, "a", 2, "b"])
        try await expect(["{returns}": ["array_zip": ["together": [[1], []]]]], equals: [])
    }

    @Test func resolves_computed_arrays() async throws {
        try await expect([
            "{returns}": [
                "array_zip": [
                    "together": [
                        ["{returns}": ["this": ["value": [1, 2]]]],
                        ["{returns}": ["this": ["value": ["one", "two"]]]],
                    ],
                ],
            ],
        ], equals: [[1, "one"], [2, "two"]])
    }
}
