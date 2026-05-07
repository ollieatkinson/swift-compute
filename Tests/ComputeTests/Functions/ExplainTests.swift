import Compute
import Testing

@Suite(.serialized)
struct ExplainTests {
    @Test func returns_the_computed_value_with_displayable_thoughts() async throws {
        let json: JSON = [
            "{returns}": [
                "explain": [
                    "value": [
                        "{returns}": [
                            "comparison": [
                                "greater_or_equal": [
                                    "lhs": ["{returns}": ["item": ["age"]]],
                                    "rhs": 36,
                                ],
                            ],
                        ],
                    ],
                ],
            ],
        ]

        #expect(try await value(json, in: Compute.Context(item: users[2])) == [
            "ok": true,
            "summary": "true",
            "thoughts": [
                [
                    "depth": 7,
                    "keyword": "item",
                    "kind": "compute",
                    "output": "36",
                    "route": ["{returns}", "explain", "value", "{returns}", "comparison", "greater_or_equal", "lhs"],
                ],
                [
                    "depth": 3,
                    "keyword": "comparison",
                    "kind": "compute",
                    "output": "true",
                    "route": ["{returns}", "explain", "value"],
                ],
            ],
            "value": true,
        ])
    }

    @Test func returns_a_useful_payload_when_the_explained_value_fails() async throws {
        let json: JSON = [
            "{returns}": [
                "explain": [
                    "value": [
                        "{returns}": [
                            "error": [
                                "message": "not available",
                            ],
                        ],
                    ],
                ],
            ],
        ]

        #expect(try await value(json) == [
            "error": "not available",
            "ok": false,
            "thoughts": [],
            "value": nil,
        ])
    }
}
