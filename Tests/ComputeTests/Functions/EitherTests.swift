import Compute
import Testing

@Suite(.serialized)
struct EitherTests {

    @Test func returnsTheFirstMatchingBranch() async throws {
        try await expect(
            [
                "{returns}": [
                    "either": [
                        [
                            "value": 1,
                            "condition": false,
                        ],
                        [
                            "value": 2,
                            "condition": ["{returns}": ["this": ["value": true]]],
                        ],
                        [
                            "value": 3,
                        ],
                    ],
                ],
            ],
            equals: 2
        )
    }

    @Test func selectsBranchUsingReferencedComputedConditions() async throws {
        let references = TestReferences()
        await references.set("data.array", to: [1, 2, 3, 4, 5, 6, 7, 8, 9])
        let count: JSON = [
            "{returns}": [
                "count": [
                    "of": ["{returns}": ["from": ["reference": "data.array"]]],
                ],
            ],
        ]
        let json: JSON = [
            "{returns}": [
                "either": [
                    [
                        "condition": [
                            "{returns}": [
                                "comparison": [
                                    "less": [
                                        "lhs": count,
                                        "rhs": 1,
                                    ],
                                ],
                            ],
                        ],
                        "value": 1,
                    ],
                    [
                        "condition": [
                            "{returns}": [
                                "comparison": [
                                    "greater": [
                                        "lhs": count,
                                        "rhs": 1,
                                    ],
                                ],
                            ],
                        ],
                        "value": 2,
                    ],
                ],
            ],
        ]

        try await expect([
            "{returns}": [
                "either": [
                    ["condition": false, "value": 1],
                    ["condition": true, "value": 2],
                ],
            ],
        ], equals: 2)
        #expect(try await runtime(json, references: references).value() == 2)
        await references.finish()
    }
}
