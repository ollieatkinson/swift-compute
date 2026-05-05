import Compute
import Testing

@Suite(.serialized)
struct MapTests {

    @Test func copiesValuesFromItsLocalItemContext() async throws {
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

    @Test func mapsIdentityEmptySourcesComputedCopiesAndIndexedPaths() async throws {
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

    @Test func copiesComputedExistsIntoNestedOutput() async throws {
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
}
