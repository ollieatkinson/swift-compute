import Compute
import Testing

@Suite(.serialized)
struct FromTests {

    @Test func publishes_every_reference_change() async throws {
        let references = TestReferences()
        await references.set("feature", to: true)
        let runtime = try runtime(["{returns}": ["from": ["reference": "feature"]]], references: references)
        var stream = runtime.run().makeAsyncIterator()

        await expectNext(&stream, equals: .success(true))
        await references.set("feature", to: false)
        await expectNext(&stream, equals: .success(false))
        await references.set("feature", to: true)
        await expectNext(&stream, equals: .success(true))

        await references.finish()
        await runtime.cancel()
    }

    @Test func recursively_resolves_referenced_computes() async throws {
        let references = TestReferences()
        await references.set("flag.pointer", to: ["{returns}": ["from": ["reference": "flag.actual"]]])
        await references.set("flag.actual", to: true)
        let runtime = try runtime(["{returns}": ["from": ["reference": "flag.pointer"]]], references: references)
        var stream = runtime.run().makeAsyncIterator()

        await expectNext(&stream, equals: .success(true))
        await references.set("flag.actual", to: false)
        await expectNext(&stream, equals: .success(false))
        await references.set("flag.actual", to: true)
        await expectNext(&stream, equals: .success(true))

        await references.finish()
        await runtime.cancel()
    }

    @Test func recursively_resolves_three_froms_into_a_comparison() async throws {
        let references = TestReferences()
        await references.set("rules.entry", to: ["{returns}": ["from": ["reference": "rules.subject.isEligible"]]])
        await references.set("rules.subject.isEligible", to: ["{returns}": ["from": ["reference": "rules.subject.eligibilityCheck"]]])
        await references.set("rules.subject.eligibilityCheck", to: [
            "{returns}": [
                "comparison": [
                    "greater_or_equal": [
                        "lhs": 21,
                        "rhs": 18,
                    ],
                ],
            ],
        ])

        let runtime = try runtime(["{returns}": ["from": ["reference": "rules.entry"]]], references: references)
        var stream = runtime.run().makeAsyncIterator()

        await expectNext(&stream, equals: .success(true))
        await references.set("rules.subject.eligibilityCheck", to: [
            "{returns}": [
                "comparison": [
                    "greater_or_equal": [
                        "lhs": 16,
                        "rhs": 18,
                    ],
                ],
            ],
        ])
        await expectNext(&stream, equals: .success(false))

        await references.finish()
        await runtime.cancel()
    }

    @Test func updates_nested_document_routes_when_a_reference_changes() async throws {
        let references = TestReferences()
        await references.set("minimum_age", to: 36)
        let document: JSON = [
            "profile": [
                "adult": [
                    "{returns}": [
                        "comparison": [
                            "greater_or_equal": [
                                "lhs": ["{returns}": ["item": ["age"]]],
                                "rhs": ["{returns}": ["from": ["reference": "minimum_age"]]],
                            ],
                        ],
                    ],
                ],
                "name": ["{returns}": ["item": ["name"]]],
            ],
        ]
        let runtime = try runtime(document, in: Compute.Context(item: users[2]), references: references)
        var adult = runtime.run(at: ["profile", "adult"]).makeAsyncIterator()

        #expect(try await runtime.value(at: ["profile", "name"]) == "Ste")
        await expectNext(&adult, equals: .success(true))
        await references.set("minimum_age", to: 40)
        await expectNext(&adult, equals: .success(false))

        await references.finish()
        await runtime.cancel()
    }

    @Test func defaults_allow_streams_to_recover_from_reference_failures() async throws {
        let references = TestReferences()
        await references.set("feature", to: true)
        let runtime = try runtime([
            "{returns}": ["from": ["reference": "feature"]],
            "default": false,
        ], references: references)
        var stream = runtime.run().makeAsyncIterator()

        await expectNext(&stream, equals: .success(true))
        await references.fail("feature", with: JSONError("network unavailable"))
        await expectNext(&stream, equals: .success(false))
        await references.set("feature", to: true)
        await expectNext(&stream, equals: .success(true))

        await references.finish()
        await runtime.cancel()
    }

    @Test func missing_defaults_publish_failures_and_recover() async throws {
        let references = TestReferences()
        await references.set("feature", to: true)
        let runtime = try runtime(["{returns}": ["from": ["reference": "feature"]]], references: references)
        var stream = runtime.run().makeAsyncIterator()

        await expectNext(&stream, equals: .success(true))
        await references.fail("feature", with: JSONError("network unavailable"))
        await expectNext(&stream, equals: .failure(JSONError("network unavailable")))
        await references.set("feature", to: false)
        await expectNext(&stream, equals: .success(false))

        await references.finish()
        await runtime.cancel()
    }

    @Test func recomputes_recursive_documents_when_dependencies_change() async throws {
        let references = TestReferences()
        await references.set("data.type.boolean", to: true)
        await references.set("data.type.integer", to: 0)
        let json: JSON = [
            "bool": [
                "{returns}": [
                    "this": [
                        "value": ["{returns}": ["from": ["reference": "data.type.boolean"]]],
                    ],
                ],
            ],
            "int": [
                "{returns}": [
                    "this": [
                        "value": [
                            "{returns}": [
                                "this": [
                                    "value": ["{returns}": ["from": ["reference": "data.type.integer"]]],
                                ],
                            ],
                        ],
                        "condition": ["{returns}": ["this": ["value": true]]],
                    ],
                ],
            ],
        ]
        let runtime = try runtime(json, references: references)
        var stream = runtime.run().makeAsyncIterator()

        await expectNext(&stream, equals: .success(["bool": true, "int": 0]))
        await references.set("data.type.boolean", to: false)
        await expectNext(&stream, equals: .success(["bool": false, "int": 0]))
        await references.set("data.type.integer", to: 2)
        await expectNext(&stream, equals: .success(["bool": false, "int": 2]))
        await references.set("data.type.integer", to: 3)
        await expectNext(&stream, equals: .success(["bool": false, "int": 3]))
        await references.set("data.type.boolean", to: true)
        await expectNext(&stream, equals: .success(["bool": true, "int": 3]))

        await references.finish()
        await runtime.cancel()
    }

    @Test func uses_context_when_resolving_references() async throws {
        let references = TestReferences()
        await references.set("feature.access.allowed?subject.id=\"example\"", to: true)
        let json: JSON = [
            "{returns}": [
                "from": [
                    "reference": "feature.access.allowed",
                    "context": [
                        "subject.id": "example",
                    ],
                ],
            ],
        ]

        #expect(try await runtime(json, references: references).value() == true)
        await references.finish()
    }

    @Test func computes_reference_and_context_before_resolving() async throws {
        let references = TestReferences()
        await references.set("feature.access.allowed?subject.id=\"example\"", to: true)
        let json: JSON = [
            "{returns}": [
                "from": [
                    "reference": ["{returns}": ["item": ["reference"]]],
                    "context": [
                        "subject.id": ["{returns}": ["item": ["subject"]]],
                    ],
                ],
            ],
        ]

        #expect(try await runtime(
            json,
            in: Compute.Context(item: [
                "reference": "feature.access.allowed",
                "subject": "example",
            ]),
            references: references
        ).value() == true)
        await references.finish()
    }
}
