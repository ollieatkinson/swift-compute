import Compute
import Testing

@Suite(.serialized)
struct BrainRuntimeBehaviorTests {
    @Test func runtime_steps_through_leaf_computes_before_replacing_the_root() async throws {
        let references = TestReferences()
        await references.set("minimum_age", to: 36)
        let json: JSON = [
            "{returns}": [
                "comparison": [
                    "greater_or_equal": [
                        "lhs": ["{returns}": ["item": ["age"]]],
                        "rhs": ["{returns}": ["from": ["reference": "minimum_age"]]],
                    ],
                ],
            ],
        ]
        let runtime = try runtime(json, in: Compute.Context(item: users[2]), references: references)
        let step = try await runtime.step()

        #expect(step.thoughts.map(\.keyword) == ["item", "from", "comparison"])
        #expect(step.thoughts.map(\.kind) == [.compute, .returns, .compute])
        #expect(outputsByRoute(in: step.thoughts) == [
            ["{returns}", "comparison", "greater_or_equal", "lhs"]: 36,
            ["{returns}", "comparison", "greater_or_equal", "rhs"]: 36,
            []: true,
        ])
        #expect(step.state == true)
        #expect(step.remainingThoughts == 0)
        #expect(step.isThinking == false)

        await references.finish()
        await runtime.cancel()
    }

    @Test func runtime_thoughts_describe_default_values() async throws {
        let json: JSON = [
            "{returns}": [
                "this": [
                    "value": "selected",
                    "condition": false,
                ],
            ],
            "default": "fallback",
        ]
        let runtime = try runtime(json)
        let step = try await runtime.step()

        #expect(step.thoughts.map(\.keyword) == ["default"])
        #expect(step.thoughts.map(\.kind) == [.defaultValue])
        #expect(step.state == "fallback")

        await runtime.cancel()
    }

    @Test func runtime_steps_the_json_state_after_each_propagation_wave() async throws {
        let references = TestReferences()
        await references.set("minimum_age", to: 36)
        let json: JSON = [
            "{returns}": [
                "comparison": [
                    "greater_or_equal": [
                        "lhs": ["{returns}": ["item": ["age"]]],
                        "rhs": ["{returns}": ["from": ["reference": "minimum_age"]]],
                    ],
                ],
            ],
        ]
        let runtime = try runtime(json, in: Compute.Context(item: users[2]), references: references)

        #expect(await runtime.remainingThoughtCount == 1)
        let step = try await runtime.step()
        #expect(step.state == true)
        #expect(step.remainingThoughts == 0)

        await references.finish()
        await runtime.cancel()
    }

    @Test func runtime_steps_through_six_mixed_sync_and_async_computes() async throws {
        let references = TestReferences()
        await references.set("minimum_age", to: 36)
        await references.set("manual_review", to: true)
        let initial: JSON = [
            "{returns}": [
                "yes": [
                    "if": [
                        [
                            "{returns}": [
                                "comparison": [
                                    "greater_or_equal": [
                                        "lhs": ["{returns}": ["item": ["age"]]],
                                        "rhs": ["{returns}": ["from": ["reference": "minimum_age"]]],
                                    ],
                                ],
                            ],
                        ],
                    ],
                    "unless": [
                        [
                            "{returns}": [
                                "not": [
                                    "{returns}": [
                                        "from": [
                                            "reference": "manual_review",
                                        ],
                                    ],
                                ],
                            ],
                        ],
                    ],
                ],
            ],
        ]
        let runtime = try runtime(
            initial,
            in: Compute.Context(item: users[2]),
            references: references
        )

        let step = try await runtime.step()
        let thoughts = step.thoughts

        #expect(thoughts.map(\.keyword) == ["item", "from", "from", "comparison", "not", "yes"])
        #expect(thoughts.map(\.kind) == [.compute, .returns, .returns, .compute, .compute, .compute])
        #expect(step.remainingThoughts == 0)
        #expect(fromReferences(in: thoughts) == ["minimum_age", "manual_review"])
        #expect(step.state == true)

        await references.finish()
        await runtime.cancel()
    }

    @Test func runtime_step_observes_all_ready_computes_from_the_deepest_wave() async throws {
        let json: JSON = [
            "left": ["{returns}": ["comparison": ["equal": ["lhs": 1, "rhs": 1]]]],
            "right": ["{returns}": ["comparison": ["equal": ["lhs": 1, "rhs": 2]]]],
        ]
        let runtime = try runtime(json)

        let step = try await runtime.step()
        #expect(Set(step.thoughts.map(\.route)) == Set<Compute.Route>([["left"], ["right"]]))
        #expect(step.state == [
            "left": true,
            "right": false,
        ])
        #expect(step.remainingThoughts == 0)
    }

    @Test func runtime_run_keeps_the_brain_alive_for_future_reference_updates() async throws {
        let references = TestReferences()
        await references.set("minimum_age", to: 38)
        let json: JSON = [
            "{returns}": [
                "comparison": [
                    "greater_or_equal": [
                        "lhs": ["{returns}": ["item": ["age"]]],
                        "rhs": ["{returns}": ["from": ["reference": "minimum_age"]]],
                    ],
                ],
            ],
        ]
        let runtime = try runtime(json, in: Compute.Context(item: users[2]), references: references)

        #expect(await runtime.remainingThoughtCount == 1)
        var events = runtime.run().makeAsyncIterator()

        #expect(await events.next() == .success(false))
        #expect(await runtime.remainingThoughtCount == 0)

        await references.set("minimum_age", to: 36)
        #expect(await events.next() == .success(true))

        await references.finish()
        await runtime.cancel()
    }

    @Test func local_context_computes_resolve_as_their_own_pond() async throws {
        let json: JSON = [
            "{returns}": [
                "array_filter": [
                    "array": [1, 2, 3, 4, 5],
                    "predicate": [
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
        ]
        let runtime = try runtime(json)

        #expect(await runtime.remainingThoughtCount == 1)
        let step = try await runtime.step()
        let keywords = step.thoughts.map(\.keyword)
        #expect(keywords.last == "array_filter")
        #expect(keywords.filter { $0 == "item" }.count == 5)
        #expect(keywords.filter { $0 == "comparison" }.count == 5)
        #expect(step.state == [1, 2, 3])
        #expect(await runtime.remainingThoughtCount == 0)
    }

    @Test func complex_local_compute_records_nested_returns_in_the_same_brain_step() async throws {
        let references = TestReferences()
        await references.set("minimum_age", to: 36)
        await references.set("city", to: "Manchester")
        await references.set("block_all", to: false)
        let json: JSON = [
            "{returns}": [
                "array_filter": [
                    "array": .array(users),
                    "predicate": [
                        "{returns}": [
                            "yes": [
                                "if": [
                                    [
                                        "{returns}": [
                                            "comparison": [
                                                "greater_or_equal": [
                                                    "lhs": ["{returns}": ["item": ["age"]]],
                                                    "rhs": ["{returns}": ["from": ["reference": "minimum_age"]]],
                                                ],
                                            ],
                                        ],
                                    ],
                                    [
                                        "{returns}": [
                                            "comparison": [
                                                "equal": [
                                                    "lhs": ["{returns}": ["item": ["address", "city"]]],
                                                    "rhs": ["{returns}": ["from": ["reference": "city"]]],
                                                ],
                                            ],
                                        ],
                                    ],
                                ],
                                "unless": [
                                    ["{returns}": ["from": ["reference": "block_all"]]],
                                ],
                            ],
                        ],
                    ],
                ],
            ],
        ]
        let runtime = try runtime(json, references: references)

        let step = try await runtime.step()
        let log = step.thoughts.map(\.keyword)

        #expect(step.remainingThoughts == 0)
        #expect(step.state == [users[2]])
        #expect(log.last == "array_filter")
        #expect(log.filter { $0 == "from" }.count == 9)
        #expect(frequencies(fromReferences(in: step.thoughts)) == [
            "minimum_age": 3,
            "city": 3,
            "block_all": 3,
        ])

        await references.finish()
        await runtime.cancel()
    }

    @Test func complex_local_compute_reacts_to_every_nested_returns_value_changing() async throws {
        let references = TestReferences()
        await references.set("minimum_age", to: 36)
        await references.set("city", to: "Manchester")
        await references.set("block_all", to: false)
        let json: JSON = [
            "{returns}": [
                "array_filter": [
                    "array": .array(users),
                    "predicate": [
                        "{returns}": [
                            "yes": [
                                "if": [
                                    [
                                        "{returns}": [
                                            "comparison": [
                                                "greater_or_equal": [
                                                    "lhs": ["{returns}": ["item": ["age"]]],
                                                    "rhs": ["{returns}": ["from": ["reference": "minimum_age"]]],
                                                ],
                                            ],
                                        ],
                                    ],
                                    [
                                        "{returns}": [
                                            "comparison": [
                                                "equal": [
                                                    "lhs": ["{returns}": ["item": ["address", "city"]]],
                                                    "rhs": ["{returns}": ["from": ["reference": "city"]]],
                                                ],
                                            ],
                                        ],
                                    ],
                                ],
                                "unless": [
                                    ["{returns}": ["from": ["reference": "block_all"]]],
                                ],
                            ],
                        ],
                    ],
                ],
            ],
        ]
        let runtime = try runtime(json, references: references)
        var stream = runtime.run().makeAsyncIterator()

        await expectNext(&stream, equals: .success([users[2]]))
        await references.set("city", to: "London")
        await expectNext(&stream, equals: .success([users[1]]))
        await references.set("minimum_age", to: 39)
        await expectNext(&stream, equals: .success([]))
        await references.set("minimum_age", to: 30)
        await expectNext(&stream, equals: .success([users[1]]))
        await references.set("block_all", to: true)
        await expectNext(&stream, equals: .success([]))
        await references.set("block_all", to: false)
        await expectNext(&stream, equals: .success([users[1]]))

        await references.finish()
        await runtime.cancel()
    }

    @Test func custom_compute_functions_can_be_standalone_runtime_nodes() async throws {
        let document: JSON = [
            "value": ["{returns}": ["echo": "typed function"]],
        ]
        let runtime = try runtime(document, in: Compute.Context(item: users[0]), functions: [Echo.function])

        #expect(try await runtime.value(at: ["value"]) == "typed function")
    }
}

private func fromReferences(in thoughts: [Compute.Thought]) -> [String] {
    thoughts.compactMap { thought in
        guard thought.keyword == "from" else { return nil }
        guard case .object(let input)? = thought.input else { return nil }
        guard case .object(let from)? = input["from"] else { return nil }
        guard case .string(let reference)? = from["reference"] else { return nil }
        return reference
    }
}

private func outputsByRoute(in thoughts: [Compute.Thought]) -> [Compute.Route: JSON] {
    thoughts.reduce(into: [:]) { outputs, thought in
        if let output = thought.output {
            outputs[thought.route] = output
        }
    }
}

private func frequencies(_ values: [String]) -> [String: Int] {
    values.reduce(into: [:]) { frequencies, value in
        frequencies[value, default: 0] += 1
    }
}
