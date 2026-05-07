import Compute
import Testing

@Suite(.serialized)
struct MembershipTests {

    @Test func evaluates_membership_in_resolved_arrays() async throws {
        try await expect(
            [
                "{returns}": [
                    "membership": [
                        "lhs": ["{returns}": ["item": ["age"]]],
                        "rhs": [36, 37, 38],
                    ],
                ],
            ],
            in: Compute.Context(item: users[1]),
            equals: true
        )
    }
}
