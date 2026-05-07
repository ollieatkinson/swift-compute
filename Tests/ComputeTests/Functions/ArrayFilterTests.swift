import Testing

@Suite(.serialized)
struct ArrayFilterTests {

    @Test func evaluates_the_predicate_for_each_item() async throws {
        try await expect(
            [
                "{returns}": [
                    "array_filter": [
                        "array": [1, 2, 3, 4, 5, 6, 7, 8, 9],
                        "predicate": [
                            "{returns}": [
                                "yes": [
                                    "if": [
                                        [
                                            "{returns}": [
                                                "comparison": [
                                                    "less": [
                                                        "lhs": ["{returns}": ["item": []]],
                                                        "rhs": 7,
                                                    ],
                                                ],
                                            ],
                                        ],
                                        [
                                            "{returns}": [
                                                "not": [
                                                    "{returns}": [
                                                        "comparison": [
                                                            "equal": [
                                                                "lhs": ["{returns}": ["item": []]],
                                                                "rhs": 5,
                                                            ],
                                                        ],
                                                    ],
                                                ],
                                            ],
                                        ],
                                    ],
                                    "unless": [
                                        [
                                            "{returns}": [
                                                "comparison": [
                                                    "less": [
                                                        "lhs": ["{returns}": ["item": []]],
                                                        "rhs": 4,
                                                    ],
                                                ],
                                            ],
                                        ],
                                    ],
                                ],
                            ],
                        ],
                    ],
                ],
            ],
            equals: [4, 6]
        )
        try await expect(
            [
                "{returns}": [
                    "array_filter": [
                        "array": [
                            ["int": 1],
                            ["int": 2],
                            ["int": 3],
                            ["int": 4],
                            ["int": 5],
                        ],
                        "predicate": [
                            "{returns}": [
                                "comparison": [
                                    "less": [
                                        "lhs": ["{returns}": ["item": ["int"]]],
                                        "rhs": 4,
                                    ],
                                ],
                            ],
                        ],
                    ],
                ],
            ],
            equals: [
                ["int": 1],
                ["int": 2],
                ["int": 3],
            ]
        )
    }

    @Test func filters_primitives_objects_counts_and_missing_fields() async throws {
        try await expect([
            "{returns}": [
                "array_filter": [
                    "array": [1, 2, 3, 4, 5, 6, 7, 8, 9],
                    "predicate": [
                        "{returns}": [
                            "yes": [
                                "if": [
                                    [
                                        "{returns}": [
                                            "comparison": [
                                                "less": [
                                                    "lhs": ["{returns}": ["item": []]],
                                                    "rhs": 7,
                                                ],
                                            ],
                                        ],
                                    ],
                                    [
                                        "{returns}": [
                                            "not": [
                                                "{returns}": [
                                                    "comparison": [
                                                        "equal": [
                                                            "lhs": ["{returns}": ["item": []]],
                                                            "rhs": 5,
                                                        ],
                                                    ],
                                                ],
                                            ],
                                        ],
                                    ],
                                ],
                                "unless": [
                                    [
                                        "{returns}": [
                                            "comparison": [
                                                "less": [
                                                    "lhs": ["{returns}": ["item": []]],
                                                    "rhs": 4,
                                                ],
                                            ],
                                        ],
                                    ],
                                ],
                            ],
                        ],
                    ],
                ],
            ],
        ], equals: [4, 6])
        try await expect([
            "{returns}": [
                "array_filter": [
                    "array": [["int": 1], ["int": 2], ["int": 3], ["bad": "thing"]],
                    "predicate": [
                        "{returns}": [
                            "exists": [
                                "value": ["{returns}": ["item": ["int"]]],
                            ],
                        ],
                    ],
                ],
            ],
        ], equals: [["int": 1], ["int": 2], ["int": 3]])
        try await expect([
            "{returns}": [
                "array_filter": [
                    "array": [
                        ["deeply": ["nested": ["ints": [1]]]],
                        ["deeply": ["nested": ["ints": [1, 1]]]],
                        ["deeply": ["nested": ["ints": [1, 1, 1]]]],
                        ["deeply": ["nested": ["ints": [1, 1, 1, 1]]]],
                    ],
                    "predicate": [
                        "{returns}": [
                            "comparison": [
                                "less": [
                                    "lhs": [
                                        "{returns}": [
                                            "count": [
                                                "of": ["{returns}": ["item": ["deeply", "nested", "ints"]]],
                                            ],
                                        ],
                                    ],
                                    "rhs": 4,
                                ],
                            ],
                        ],
                    ],
                ],
            ],
        ], equals: [
            ["deeply": ["nested": ["ints": [1]]]],
            ["deeply": ["nested": ["ints": [1, 1]]]],
            ["deeply": ["nested": ["ints": [1, 1, 1]]]],
        ])
    }

    @Test func filters_with_defaults_and_computed_array_inputs() async throws {
        try await expect([
            "{returns}": [
                "array_filter": [
                    "array": [["display": false], ["display": true], ["display": true], ["display": false]],
                    "predicate": [
                        "{returns}": ["item": ["display"]],
                        "default": true,
                    ],
                ],
            ],
        ], equals: [["display": true], ["display": true]])
        try await expect([
            "{returns}": [
                "array_filter": [
                    "array": [["hide": false], ["hide": true], ["slide": true], ["hide": false]],
                    "predicate": [
                        "{returns}": [
                            "yes": [
                                "unless": [
                                    ["{returns}": ["item": ["hide"]]],
                                ],
                            ],
                        ],
                        "default": true,
                    ],
                ],
            ],
        ], equals: [["hide": false], ["slide": true], ["hide": false]])
        try await expect([
            "{returns}": [
                "array_filter": [
                    "array": ["{returns}": ["this": ["value": [1, 2, 3, 4, 5]]]],
                    "predicate": true,
                ],
            ],
        ], equals: [1, 2, 3, 4, 5])
        try await expect([
            "{returns}": [
                "array_filter": [
                    "array": [
                        ["{returns}": ["this": ["value": 1]]],
                        ["{returns}": ["this": ["value": 2]]],
                        ["{returns}": ["this": ["value": 3]]],
                    ],
                    "predicate": true,
                ],
            ],
        ], equals: [1, 2, 3])
        try await expect([
            "{returns}": [
                "array_filter": [
                    "array": [1, 2, 3],
                    "predicate": false,
                ],
            ],
        ], equals: [])
    }
}
