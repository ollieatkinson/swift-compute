import Compute
import Testing

@Suite(.serialized)
struct ThisTests {

    @Test func returns_values_when_conditions_pass_and_defaults_when_they_do_not() async throws {
        try await expect(["{returns}": ["this": ["value": "selected"]]], equals: "selected")
        try await expect(
            [
                "{returns}": [
                    "this": [
                        "value": "selected",
                        "condition": [
                            "{returns}": [
                                "comparison": [
                                    "equal": [
                                        "lhs": ["{returns}": ["item": ["name"]]],
                                        "rhs": "Ste",
                                    ],
                                ],
                            ],
                        ],
                    ],
                ],
            ],
            in: Compute.Context(item: users[2]),
            equals: "selected"
        )
        try await expect(
            [
                "{returns}": [
                    "this": [
                        "value": "selected",
                        "condition": false,
                    ],
                ],
                "default": ["{returns}": ["this": ["value": "fallback"]]],
            ],
            equals: "fallback"
        )
    }

    @Test func resolves_raw_dictionary_payloads_defaults_and_nested_this_computes() async throws {
        let nested: JSON = [
            "{returns}": [
                "this": [
                    "value": [
                        "{returns}": [
                            "this": [
                                "value": 42,
                                "condition": true,
                            ],
                        ],
                    ],
                    "condition": ["{returns}": ["this": ["value": true]]],
                ],
            ],
        ]

        try await expect(["{returns}": ["this": ["value": "five"]]], equals: "five")
        try await expect(["{returns}": ["this": ["value": 42, "condition": true]]], equals: 42)
        try await expect([
            "{returns}": ["this": ["value": 42, "condition": false]],
            "default": "forty_two",
        ], equals: "forty_two")
        try await expect(nested, equals: 42)
    }

    @Test func defaults_can_be_computed_from_references() async throws {
        let references = TestReferences()
        await references.set("data.type.string", to: "b")
        let json: JSON = [
            "{returns}": [
                "this": [
                    "value": "a",
                    "condition": false,
                ],
            ],
            "default": [
                "{returns}": [
                    "from": [
                        "reference": "data.type.string",
                    ],
                ],
            ],
        ]

        #expect(try await runtime(json, references: references).value() == "b")
        await references.finish()
    }

    @Test func gates_nested_documents_with_referenced_comparisons() async throws {
        let references = TestReferences()
        await references.set("device.os.version", to: "17.1")
        let json: JSON = [
            "minimumAppVersion": [
                "{returns}": [
                    "this": [
                    "value": "202310.3.0",
                    "condition": [
                        "{returns}": [
                            "comparison": [
                                "equal": [
                                    "lhs": [
                                        "{returns}": [
                                            "from": [
                                                "reference": "device.os.version",
                                            ],
                                        ],
                                    ],
                                    "rhs": "17.1",
                                ],
                            ],
                        ],
                    ],
                ],
                ],
                "default": "202309.1.2",
            ],
        ]

        let runtime = try runtime(json, references: references)
        let value = try await runtime.value()
        #expect(value == ["minimumAppVersion": "202310.3.0"])
        await references.finish()
    }

    @Test func gates_on_the_count_of_a_referenced_array() async throws {
        let references = TestReferences()
        await references.set("data.type.array.of.strings", to: [])
        let reference: JSON = [
            "{returns}": [
                "from": [
                    "reference": "data.type.array.of.strings",
                ],
            ],
        ]
        let count: JSON = [
            "{returns}": [
                "count": [
                    "of": reference,
                ],
            ],
        ]
        let isEmpty: JSON = [
            "{returns}": [
                "comparison": [
                    "equal": [
                        "lhs": count,
                        "rhs": 0,
                    ],
                ],
            ],
        ]

        #expect(try await runtime(reference, references: references).value() == [])
        #expect(try await runtime(count, references: references).value() == 0)
        #expect(try await runtime(isEmpty, references: references).value() == true)
        #expect(try await runtime(
            [
                "{returns}": [
                    "this": [
                        "value": ["a"],
                        "condition": isEmpty,
                    ],
                ],
                "default": ["b"],
            ],
            references: references
        ).value() == ["a"])
        await references.finish()
    }
}
