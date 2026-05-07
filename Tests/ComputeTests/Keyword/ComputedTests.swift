import Compute
import Testing

@Suite
struct ComputedTests {
    @Test func decoder_coding_paths_drive_computed_routes() async throws {
        let scopedItem: JSON = ["id": 42]
        let actual = try await value(
            [
                "{returns}": [
                    "computed_route_probe": [
                        "context": [
                            "alpha": ["{returns}": ["route_probe": "alpha"]],
                            "beta": ["{returns}": ["route_probe": "beta"]],
                        ],
                        "entries": [
                            ["value": ["{returns}": ["route_probe": "zero"]]],
                            ["value": ["{returns}": ["route_probe": "one"]]],
                        ],
                        "expression": ["{returns}": ["route_probe": "expression"]],
                    ],
                ],
            ],
            functions: [ComputedRouteProbe.function, RouteProbeFunction()]
        )

        let base: [Compute.Route.Component] = [
            .key("{returns}"),
            .key("computed_route_probe"),
        ]

        #expect(actual == [
            "context": [
                "alpha": frameSummary(
                    route: base + [
                        .key("context"),
                        .key("alpha"),
                        .key("{returns}"),
                        .key("route_probe"),
                    ],
                    depth: 0,
                    input: "alpha"
                ),
                "beta": frameSummary(
                    route: base + [
                        .key("context"),
                        .key("beta"),
                        .key("{returns}"),
                        .key("route_probe"),
                    ],
                    depth: 0,
                    input: "beta"
                ),
            ],
            "entry_one_with_item": frameSummary(
                route: base + [
                    .key("entries"),
                    .index(1),
                    .key("value"),
                    .key("suffix"),
                    .key("{returns}"),
                    .key("route_probe"),
                ],
                depth: 1,
                item: scopedItem,
                input: "one"
            ),
            "entry_zero": frameSummary(
                route: base + [
                    .key("entries"),
                    .index(0),
                    .key("value"),
                    .key("{returns}"),
                    .key("route_probe"),
                ],
                depth: 0,
                input: "zero"
            ),
            "expression": frameSummary(
                route: base + [.key("expression"), .key("{returns}"), .key("route_probe")],
                depth: 0,
                input: "expression"
            ),
        ])
    }

    @Test func typed_computed_arrays_compute_each_element_before_decoding() async throws {
        let actual = try await value(
            [
                "{returns}": [
                    "typed_computed_probe": [
                        "conditions": [
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
            in: Compute.Context(item: ["enabled": true]),
            functions: [TypedComputedProbe.function]
        )

        #expect(actual == [
            "conditions": [true, true, true],
            "missing_optional": true,
        ])
    }
}

private struct ComputedRouteProbe: Compute.KeywordDefinition {
    static let name = "computed_route_probe"

    @Computed var expression: JSON
    @Computed var context: [String: JSON]?
    let entries: [Entry]

    struct Entry: Codable, Equatable, Sendable {
        @Computed var value: JSON
    }

    func compute(in frame: Compute.Frame) async throws -> JSON? {
        let item: JSON = ["id": 42]
        return [
            "context": .object(try await $context.compute(in: frame) ?? [:]),
            "entry_one_with_item": try await entries[1].$value.compute(
                in: frame,
                item: item,
                appending: "suffix"
            ),
            "entry_zero": try await entries[0].$value.compute(in: frame),
            "expression": try await $expression.compute(in: frame),
        ]
    }
}

private struct TypedComputedProbe: Compute.KeywordDefinition {
    static let name = "typed_computed_probe"

    @Computed var conditions: [Bool]
    @Computed var optional: [Bool]?

    func compute(in frame: Compute.Frame) async throws -> JSON? {
        let conditions = try await $conditions.compute(in: frame)
        let optional = try await $optional.compute(in: frame)
        return [
            "conditions": .array(conditions.map(JSON.bool)),
            "missing_optional": .bool(optional == nil),
        ]
    }
}
