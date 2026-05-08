import Compute
import Testing

#if canImport(FoundationModels) && (os(iOS) || os(macOS))
import FoundationModels
#endif

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
                    "mode": "trace",
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

#if canImport(FoundationModels) && (os(iOS) || os(macOS))
    @Test
    func foundationModelModeProducesAStringExplanation() async throws {
        if #available(iOS 26.0, macOS 26.0, *) {
            guard SystemLanguageModel.default.isAvailable else {
                print("Skipping foundation_model explanation assertion: \(SystemLanguageModel.default.availability)")
                return
            }
        } else {
            print("Skipping foundation_model explanation assertion: requires iOS 26+ or macOS 26+.")
            return
        }

        let references = TestReferences()
        await references.set("device.profile.age", to: 36)
        await references.set("device.profile.loyalty_tier", to: "gold")
        await references.set("device.network.is_online", to: true)
        await references.set("device.battery.level_percent", to: 74)
        await references.set("server.flight.minimum_boarding_age", to: 36)
        await references.set("server.flight.allowed_loyalty_tiers", to: ["gold", "platinum"])
        await references.set("server.flight.boarding_open", to: true)
        await references.set("server.flight.manual_review_required", to: false)

        let json: JSON = [
            "{returns}": [
                "explain": [
                    "context": [
                        "label": "Boarding eligibility",
                        "purpose": "explains why the user is seeing the ready-to-board state",
                        "surface": "flight boarding status tooltip",
                    ],
                    "mode": "foundation_model",
                    "value": [
                        "{returns}": [
                            "yes": [
                                "if": [
                                    [
                                        "{returns}": [
                                            "comparison": [
                                                "greater_or_equal": [
                                                    "lhs": ["{returns}": ["from": ["reference": "device.profile.age"]]],
                                                    "rhs": ["{returns}": ["from": ["reference": "server.flight.minimum_boarding_age"]]],
                                                ],
                                            ],
                                        ],
                                    ],
                                    [
                                        "{returns}": [
                                            "contains": [
                                                "lhs": ["{returns}": ["from": ["reference": "server.flight.allowed_loyalty_tiers"]]],
                                                "rhs": ["{returns}": ["from": ["reference": "device.profile.loyalty_tier"]]],
                                            ],
                                        ],
                                    ],
                                    ["{returns}": ["from": ["reference": "server.flight.boarding_open"]]],
                                    ["{returns}": ["from": ["reference": "device.network.is_online"]]],
                                    [
                                        "{returns}": [
                                            "comparison": [
                                                "greater_or_equal": [
                                                    "lhs": ["{returns}": ["from": ["reference": "device.battery.level_percent"]]],
                                                    "rhs": 20,
                                                ],
                                            ],
                                        ],
                                    ],
                                ],
                                "unless": [
                                    "{returns}": ["from": ["reference": "server.flight.manual_review_required"]],
                                ],
                            ],
                        ],
                    ],
                ],
            ],
        ]

        let output = try await value(json, functions: [Compute.Keyword.From.Function(references: references)])

        guard case .object(let payload) = output else {
            Issue.record("Expected explain to return an object, got \(output)")
            await references.finish()
            return
        }
        guard case .string(let explanation)? = payload["explanation"] else {
            Issue.record("Expected foundation_model explain output to include a string explanation, got \(output)")
            await references.finish()
            return
        }

        print("foundation_model explanation: \(explanation)")
        #expect(!explanation.isEmpty)
        await references.finish()
    }
#endif
}
