import Compute
import Testing

@Suite(.serialized)
struct MembershipTests {

    @Test func evaluatesMembershipInResolvedArrays() async throws {
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
