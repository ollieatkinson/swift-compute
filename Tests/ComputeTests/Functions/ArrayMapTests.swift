import Testing

@Suite(.serialized)
struct ArrayMapTests {

    @Test func copiesIntoObjectsAndFlattensArrays() async throws {
        try await expect(
            [
                "{returns}": [
                    "array_map": [
                        "over": [1, 2, 3],
                        "copy": [
                            [
                                "value": ["{returns}": ["item": []]],
                                "to": ["int"],
                            ],
                        ],
                    ],
                ],
            ],
            equals: [
                ["int": 1],
                ["int": 2],
                ["int": 3],
            ]
        )
        try await expect(
            [
                "{returns}": [
                    "array_map": [
                        "over": [["int": 1], ["int": 2]],
                        "copy": [
                            [
                                "value": ["{returns}": ["item": ["int"]]],
                                "to": ["copy"],
                            ],
                        ],
                        "into_self": true,
                    ],
                ],
            ],
            equals: [
                ["int": 1, "copy": 1],
                ["int": 2, "copy": 2],
            ]
        )
        try await expect(
            [
                "{returns}": [
                    "array_map": [
                        "over": [[1], [2, 3], 4],
                        "flattened": true,
                    ],
                ],
            ],
            equals: [1, 2, 3, 4]
        )
    }

    @Test func mapsIdentityFlattensMixedArraysAndCopiesIntoExistingObjects() async throws {
        try await expect(["{returns}": ["array_map": ["over": [1, 2, 3, 4, 5, 6, 7, 8, 9]]]], equals: [1, 2, 3, 4, 5, 6, 7, 8, 9])
        try await expect(["{returns}": ["array_map": ["over": [], "flattened": true]]], equals: [])
        try await expect([
            "{returns}": [
                "array_map": [
                    "over": [0, [1, 2, 3], [4, 5, 6], 7],
                    "flattened": true,
                ],
            ],
        ], equals: [0, 1, 2, 3, 4, 5, 6, 7])
        try await expect([
            "{returns}": [
                "array_map": [
                    "over": [1, 2, 3],
                    "copy": [
                        [
                            "value": ["{returns}": ["item": []]],
                            "to": ["int"],
                        ],
                    ],
                ],
            ],
        ], equals: [["int": 1], ["int": 2], ["int": 3]])
        try await expect([
            "{returns}": [
                "array_map": [
                    "over": [["int": 1], ["int": 2], ["int": 3]],
                    "copy": [
                        [
                            "value": [
                                "{returns}": [
                                    "exists": [
                                        "value": ["{returns}": ["item": ["int"]]],
                                    ],
                                ],
                            ],
                            "to": ["has", "int"],
                        ],
                    ],
                    "into_self": true,
                ],
            ],
        ], equals: [
            ["int": 1, "has": ["int": true]],
            ["int": 2, "has": ["int": true]],
            ["int": 3, "has": ["int": true]],
        ])
    }

    @Test func flattensCopiedNestedAndIndexedSubpaths() async throws {
        try await expect([
            "{returns}": [
                "array_map": [
                    "over": [
                        ["items": [1]],
                        ["items": [2, 3]],
                        ["items": [4, 5, 6]],
                    ],
                    "flattened": true,
                    "copy": [
                        [
                            "value": ["{returns}": ["item": ["items"]]],
                            "to": [],
                        ],
                    ],
                ],
            ],
        ], equals: [1, 2, 3, 4, 5, 6])
        try await expect([
            "{returns}": [
                "array_map": [
                    "over": [
                        ["items": [["y": "a", "x": 1]]],
                        ["items": [["y": "b", "x": 2], ["y": "c", "x": 3]]],
                        ["items": [["y": "d", "x": 4]]],
                    ],
                    "flattened": true,
                    "copy": [
                        [
                            "value": ["{returns}": ["item": ["items", 0, "x"]]],
                            "to": [],
                        ],
                    ],
                ],
            ],
        ], equals: [1, 2, 4])
    }
}
