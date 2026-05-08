import Compute
import Testing

@Suite(.serialized)
struct ContainsTests {

    @Test func evaluates_string_containment() async throws {
        let json: JSON = [
            "{returns}": [
                "contains": [
                    "lhs": ["{returns}": ["item": ["name"]]],
                    "rhs": "os",
                ],
            ],
        ]

        try await expect(json, in: Compute.Context(item: users[0]), equals: true)
        try await expect(json, in: Compute.Context(item: users[1]), equals: false)
    }

    @Test func evaluates_array_containment() async throws {
        try await expect(
            [
                "{returns}": [
                    "contains": [
                        "lhs": [36, 37, 38],
                        "rhs": ["{returns}": ["item": ["age"]]],
                    ],
                ],
            ],
            in: Compute.Context(item: users[1]),
            equals: true
        )
    }
}
