import Compute
import Testing

@Suite(.serialized)
struct YesTests {

    @Test func composes_nested_boolean_computes() async throws {
        try await expect(
            [
                "{returns}": [
                    "yes": [
                        "if": [
                            true,
                            [
                                "{returns}": [
                                    "comparison": [
                                        "greater": [
                                            "lhs": ["{returns}": ["item": ["age"]]],
                                            "rhs": 30,
                                        ],
                                    ],
                                ],
                            ],
                        ],
                        "unless": [
                            ["{returns}": ["item": ["isClearToFly"]]],
                        ],
                    ],
                ],
            ],
            in: Compute.Context(item: users[2]),
            equals: true
        )
    }

    @Test func resolves_nested_unless_conditions_before_combining_booleans() async throws {
        let nestedThisUnless: JSON = [
            "{returns}": [
                "yes": [
                    "if": [true, true],
                    "unless": [
                        "{returns}": [
                            "this": [
                                "value": [
                                    ["{returns}": ["yes": ["unless": [true]]]],
                                    false,
                                ],
                            ],
                        ],
                    ],
                ],
            ],
        ]

        try await expect(["{returns}": ["yes": ["if": [true, true], "unless": [false, false]]]], equals: true)
        try await expect([
            "{returns}": [
                "yes": [
                    "if": [true, true],
                    "unless": ["{returns}": ["this": ["value": [false, false]]]],
                ],
            ],
        ], equals: true)
        try await expect([
            "{returns}": [
                "yes": [
                    "if": [true, true],
                    "unless": [
                        ["{returns}": ["yes": ["unless": [true]]]],
                        false,
                    ],
                ],
            ],
        ], equals: true)
        try await expect(nestedThisUnless, equals: true)
    }

    @Test func resolves_computed_condition_arrays_and_elements() async throws {
        try await expect([
            "{returns}": [
                "yes": [
                    "if": [
                        "{returns}": [
                            "this": [
                                "value": [
                                    true,
                                    ["{returns}": ["not": false]],
                                    [
                                        "{returns}": [
                                            "comparison": [
                                                "equal": [
                                                    "lhs": ["{returns}": ["item": ["enabled"]]],
                                                    "rhs": true,
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
        ], in: Compute.Context(item: ["enabled": true]), equals: true)

        try await expect([
            "{returns}": [
                "yes": [
                    "if": [
                        true,
                        ["{returns}": ["not": false]],
                    ],
                    "unless": [
                        ["{returns}": ["this": ["value": false]]],
                    ],
                ],
            ],
        ], equals: true)
    }
}
