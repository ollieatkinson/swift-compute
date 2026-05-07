import Testing

@Suite(.serialized)
struct NotTests {

    @Test func negates_literal_and_nested_comparison_values() async throws {
        try await expect(["{returns}": ["not": false]], equals: true)
        try await expect(["{returns}": ["not": true]], equals: false)
        try await expect([
            "{returns}": [
                "not": ["{returns}": ["comparison": ["equal": ["lhs": 1, "rhs": 1]]]],
            ],
        ], equals: false)
        try await expect([
            "{returns}": [
                "not": ["{returns}": ["comparison": ["equal": ["lhs": 1, "rhs": 2]]]],
            ],
        ], equals: true)
    }
}
