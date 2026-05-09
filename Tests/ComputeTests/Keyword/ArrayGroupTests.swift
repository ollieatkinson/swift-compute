import Compute
import Testing

@Suite(.serialized)
struct ArrayGroupTests {

    @Test func groups_into_counts_with_overflow_policies() async throws {
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

    @Test func groups_by_computed_item_value_and_orders_groups() async throws {
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
        ], in: Compute.Context(item: ["category": "outer"]), equals: [
            [["category": "a", "name": "A1"]],
            [["category": "b", "name": "B1"], ["category": "b", "name": "B2"]],
        ])
    }

    @Test func resolves_computed_into_options() async throws {
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

    @Test func computes_into_plan_before_grouping() async throws {
        try await expect([
            "{returns}": [
                "array_group": [
                    "array": [1, 2, 3, 4, 5],
                    "into": [
                        "{returns}": [
                            "this": [
                                "value": [
                                    "counts": [
                                        ["{returns}": ["item": ["count"]]],
                                    ],
                                    "overflow": ["{returns}": ["item": ["overflow"]]],
                                ],
                            ],
                        ],
                    ],
                ],
            ],
        ], in: Compute.Context(item: [
            "count": 2,
            "overflow": "patterned",
        ]), equals: [[1, 2], [3, 4]])
    }
}
