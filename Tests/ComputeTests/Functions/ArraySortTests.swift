import Compute
import Testing

@Suite(.serialized)
struct ArraySortTests {

    @Test func sorts_values_and_objects_with_stable_fallbacks() async throws {
        try await expect(["{returns}": ["array_sort": ["array": [3, 1, 2], "predicates": [["order": "ascending"]]]]], equals: [1, 2, 3])
        try await expect(["{returns}": ["array_sort": ["array": ["b", "c", "a"], "predicates": [["order": "descending"]]]]], equals: ["c", "b", "a"])
        try await expect([
            "{returns}": [
                "array_sort": [
                    "array": [
                        ["name": "b", "rank": 2],
                        ["name": "a", "rank": 1],
                        ["name": "c", "rank": 2],
                    ],
                    "predicates": [
                        ["key_path": ["rank"], "order": "ascending"],
                        ["key_path": ["name"], "order": "descending"],
                    ],
                ],
            ],
        ], equals: [
            ["name": "a", "rank": 1],
            ["name": "c", "rank": 2],
            ["name": "b", "rank": 2],
        ])
    }

    @Test func returns_identity_without_predicates() async throws {
        try await expect(["{returns}": ["array_sort": ["array": [3, 1, 2]]]], equals: [3, 1, 2])
    }

    @Test func resolves_computed_array_inputs() async throws {
        try await expect(
            [
                "{returns}": [
                    "array_sort": [
                        "array": ["{returns}": ["item": ["scores"]]],
                        "predicates": [["order": "ascending"]],
                    ],
                ],
            ],
            in: Compute.Context(item: ["scores": [3, 1, 2]]),
            equals: [1, 2, 3]
        )
    }
}
