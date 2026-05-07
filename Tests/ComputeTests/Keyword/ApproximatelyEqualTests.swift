import Compute
import Testing

@Suite(.serialized)
struct ApproximatelyEqualTests {

    @Test func evaluates_numeric_accuracy() async throws {
        try await expect(
            [
                "{returns}": [
                    "approximately_equal": [
                        "lhs": ["{returns}": ["item": ["weight"]]],
                        "rhs": 85.0,
                        "accuracy": 4.0,
                    ],
                ],
            ],
            in: Compute.Context(item: users[2]),
            equals: true
        )
    }
}
