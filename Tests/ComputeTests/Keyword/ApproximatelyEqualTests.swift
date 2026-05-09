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
                        "accuracy": ["{returns}": ["item": ["tolerance"]]],
                    ],
                ],
            ],
            in: Compute.Context(item: [
                "tolerance": 4.0,
                "weight": 85.8,
            ]),
            equals: true
        )
    }
}
