import Testing

@Suite(.serialized)
struct ArrayGroupTests {

    @Test func groupsIntoCountsWithOverflowPolicies() async throws {
        try await expect([
            "{returns}": [
                "array_group": [
                    "array": [1, 2, 3, 4, 5, 6, 7, 8, 9],
                    "into": ["counts": [1, 2, 3]],
                ],
            ],
        ], equals: [[1], [2, 3], [4, 5, 6]])
        try await expect([
            "{returns}": [
                "array_group": [
                    "array": [1, 2, 3, 4, 5, 6, 7, 8, 9],
                    "into": ["counts": [1, 2, 3], "overflow": "patterned"],
                ],
            ],
        ], equals: [[1], [2, 3], [4, 5, 6], [7], [8, 9]])
        try await expect([
            "{returns}": [
                "array_group": [
                    "array": [1, 2, 3, 4, 5, 6, 7, 8, 9],
                    "into": ["counts": [1, 2, 3], "overflow": "grouped"],
                ],
            ],
        ], equals: [[1], [2, 3], [4, 5, 6], [7, 8, 9]])
    }

    @Test func groupsByComputedItemValueAndOrdersGroups() async throws {
        try await expect([
            "{returns}": [
                "array_group": [
                    "array": [
                        ["category": "b", "name": "B1"],
                        ["category": "a", "name": "A1"],
                        ["category": "b", "name": "B2"],
                    ],
                    "by": [
                        "value": ["{returns}": ["item": ["category"]]],
                        "order": "ascending",
                    ],
                ],
            ],
        ], equals: [
            [["category": "a", "name": "A1"]],
            [["category": "b", "name": "B1"], ["category": "b", "name": "B2"]],
        ])
    }

    @Test func resolvesComputedIntoOptions() async throws {
        try await expect([
            "{returns}": [
                "array_group": [
                    "array": [1, 2, 3, 4, 5],
                    "into": [
                        "counts": ["{returns}": ["this": ["value": [2]]]],
                        "overflow": ["{returns}": ["this": ["value": "patterned"]]],
                    ],
                ],
            ],
        ], equals: [[1, 2], [3, 4]])
    }
}
