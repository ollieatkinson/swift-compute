import Compute
import Testing

@Suite(.serialized)
struct YesTests {

    @Test func composesNestedBooleanComputes() async throws {
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

    @Test func resolvesNestedUnlessConditionsBeforeCombiningBooleans() async throws {
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
}
