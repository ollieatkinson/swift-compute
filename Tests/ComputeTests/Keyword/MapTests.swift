import Compute
import Testing

@Suite(.serialized)
struct MapTests {

    @Test func copies_values_from_its_local_item_context() async throws {
        try await expect(["{returns}": ["map": ["src": 4]]], equals: 4)
        try await expect(
            [
                "{returns}": [
                    "map": [
                        "src": 4,
                        "dst": [:],
                        "copy": [
                            [
                                "value": ["{returns}": ["item": []]],
                                "to": ["int"],
                            ],
                        ],
                    ],
                ],
            ],
            equals: ["int": 4]
        )
        try await expect(
            [
                "{returns}": [
                    "map": [
                        "src": [
                            "rectangle": [
                                "x": 1,
                                "y": 2,
                                "width": 3,
                                "height": 4,
                            ],
                        ],
                        "dst": [:],
                        "copy": [
                            [
                                "value": ["{returns}": ["item": ["rectangle", "x"]]],
                                "to": ["origin", "x"],
                            ],
                            [
                                "value": ["{returns}": ["item": ["rectangle", "y"]]],
                                "to": ["origin", "y"],
                            ],
                            [
                                "value": ["{returns}": ["item": ["rectangle", "width"]]],
                                "to": ["size", "width"],
                            ],
                            [
                                "value": ["{returns}": ["item": ["rectangle", "height"]]],
                                "to": ["size", "height"],
                            ],
                        ],
                    ],
                ],
            ],
            equals: [
                "origin": ["x": 1, "y": 2],
                "size": ["width": 3, "height": 4],
            ]
        )
    }

    @Test func copy_values_use_the_source_item_not_the_outer_item() async throws {
        try await expect(
            [
                "{returns}": [
                    "map": [
                        "src": [
                            "name": "source",
                        ],
                        "dst": [:],
                        "copy": [
                            [
                                "value": ["{returns}": ["item": ["name"]]],
                                "to": ["copied"],
                            ],
                        ],
                    ],
                ],
            ],
            in: Compute.Context(item: ["name": "outer"]),
            equals: ["copied": "source"]
        )
    }

    @Test func copy_plan_can_be_computed_from_the_source_item() async throws {
        try await expect(
            [
                "{returns}": [
                    "map": [
                        "src": [
                            "name": "source",
                            "target": "copied",
                        ],
                        "dst": [:],
                        "copy": [
                            "{returns}": [
                                "this": [
                                    "value": [
                                        [
                                            "value": ["{returns}": ["item": ["name"]]],
                                            "to": [
                                                ["{returns}": ["item": ["target"]]],
                                            ],
                                        ],
                                    ],
                                ],
                            ],
                        ],
                    ],
                ],
            ],
            in: Compute.Context(item: [
                "name": "outer",
                "target": "wrong",
            ]),
            equals: ["copied": "source"]
        )
    }

    @Test func maps_identity_empty_sources_computed_copies_and_indexed_paths() async throws {
        try await expect([
            "{returns}": [
                "map": [
                    "src": 4,
                    "copy": [
                        [
                            "value": ["{returns}": ["item": []]],
                            "to": [],
                        ],
                    ],
                ],
            ],
        ], equals: 4)
        try await expect([
            "{returns}": [
                "map": [
                    "src": [:],
                    "copy": [
                        [
                            "value": 1,
                            "to": ["one"],
                        ],
                        [
                            "value": 2,
                            "to": ["two"],
                        ],
                    ],
                ],
            ],
        ], equals: ["one": 1, "two": 2])
        try await expect([
            "{returns}": [
                "map": [
                    "src": ["nested": ["ints": [1, 2, 3, 4, 5]]],
                    "copy": [
                        [
                            "value": [
                                "{returns}": [
                                    "count": [
                                        "of": ["{returns}": ["item": ["nested", "ints"]]],
                                    ],
                                ],
                            ],
                            "to": ["count"],
                        ],
                    ],
                ],
            ],
        ], equals: ["nested": ["ints": [1, 2, 3, 4, 5]], "count": 5])
        try await expect([
            "{returns}": [
                "map": [
                    "src": ["rectangle": [1, 2, 3, 4]],
                    "dst": [:],
                    "copy": [
                        [
                            "value": ["{returns}": ["item": ["rectangle", 0]]],
                            "to": ["origin", "x"],
                        ],
                        [
                            "value": ["{returns}": ["item": ["rectangle", 1]]],
                            "to": ["origin", "y"],
                        ],
                        [
                            "value": ["{returns}": ["item": ["rectangle", 2]]],
                            "to": ["size", "width"],
                        ],
                        [
                            "value": ["{returns}": ["item": ["rectangle", 3]]],
                            "to": ["size", "height"],
                        ],
                    ],
                ],
            ],
        ], equals: [
            "origin": ["x": 1, "y": 2],
            "size": ["width": 3, "height": 4],
        ])
    }

    @Test func copies_computed_exists_into_nested_output() async throws {
        let json: JSON = [
            "{returns}": [
                "map": [
                    "src": ["nested": ["thing": 5]],
                    "copy": [
                        [
                            "value": [
                                "{returns}": [
                                    "exists": [
                                        "value": ["{returns}": ["item": ["nested", "thing"]]],
                                    ],
                                ],
                            ],
                            "to": ["is", "a", "thing"],
                        ],
                    ],
                ],
            ],
        ]

        try await expect(json, equals: [
            "nested": ["thing": 5],
            "is": ["a": ["thing": true]],
        ])
    }

    @Test func resolves_computes_inside_source_and_destination() async throws {
        try await expect([
            "{returns}": [
                "map": [
                    "src": [
                        "{returns}": [
                            "this": [
                                "value": [
                                    "values": [
                                        1,
                                        ["{returns}": ["count": ["of": [1, 2, 3]]]],
                                    ],
                                ],
                            ],
                        ],
                    ],
                    "dst": [
                        "values": [
                            0,
                            ["{returns}": ["item": ["values", 1]]],
                        ],
                    ],
                    "copy": [
                        [
                            "value": ["{returns}": ["item": ["values"]]],
                            "to": ["copied"],
                        ],
                    ],
                ],
            ],
        ], equals: [
            "values": [0, 3],
            "copied": [1, 3],
        ])
    }
}
