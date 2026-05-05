import Compute
import Testing

@Suite(.serialized)
struct GreaterOrEqualTests {

    @Test func evaluatesInclusiveOrdering() async throws {
        try await expect(["{returns}": ["comparison": ["greater_or_equal": ["lhs": 1, "rhs": 2]]]], equals: false)
        try await expect(["{returns}": ["comparison": ["greater_or_equal": ["lhs": 2, "rhs": 2]]]], equals: true)
    }

    @Test func recomputesWhenAReferencedOperandChanges() async throws {
        let references = TestReferences()
        await references.set("minimum_age", to: 38)
        let runtime = try runtime(
            [
                "{returns}": [
                    "comparison": [
                        "greater_or_equal": [
                            "lhs": ["{returns}": ["item": ["age"]]],
                            "rhs": ["{returns}": ["from": ["reference": "minimum_age"]]],
                        ],
                    ],
                ],
            ],
            in: Compute.Context(item: users[2]),
            references: references
        )
        var stream = runtime.run().makeAsyncIterator()

        await expectNext(&stream, equals: .success(false))
        await references.set("minimum_age", to: 36)
        await expectNext(&stream, equals: .success(true))
        await references.set("minimum_age", to: 40)
        await expectNext(&stream, equals: .success(false))

        await references.finish()
        await runtime.cancel()
    }
}
