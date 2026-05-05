import Testing

@Suite(.serialized)
struct EqualTests {

    @Test func comparesTypedNumbersStringsAndArrays() async throws {
        try await expect(["{returns}": ["comparison": ["equal": ["lhs": 1, "rhs": 1]]]], equals: true)
        try await expect(["{returns}": ["comparison": ["equal": ["lhs": 1.0, "rhs": 1.0]]]], equals: true)
        try await expect(["{returns}": ["comparison": ["equal": ["lhs": 1, "rhs": 1.0]]]], equals: false)
        try await expect(["{returns}": ["comparison": ["equal": ["lhs": 1, "rhs": 2]]]], equals: false)
        try await expect(["{returns}": ["comparison": ["equal": ["lhs": "42", "rhs": "42"]]]], equals: true)
        try await expect(["{returns}": ["comparison": ["equal": ["lhs": [1, 2, 3], "rhs": [1, 2, 3]]]]], equals: true)
    }

    @Test func comparesNestedJSONStructurally() async throws {
        try await expect([
            "{returns}": [
                "comparison": [
                    "equal": [
                        "lhs": ["values": [1, 2.0], "count": 2],
                        "rhs": ["values": [1, 2.0], "count": 2],
                    ],
                ],
            ],
        ], equals: true)
        try await expect([
            "{returns}": [
                "comparison": [
                    "equal": [
                        "lhs": ["values": [1, 2.0], "count": 2],
                        "rhs": ["values": [1.0, 2], "count": 2.0],
                    ],
                ],
            ],
        ], equals: false)
    }
}
