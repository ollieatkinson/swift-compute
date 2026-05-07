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
}
