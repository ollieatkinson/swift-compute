import Compute
import Testing

@Suite(.serialized)
struct ItemTests {

    @Test func readsValuesFromLocalContext() async throws {
        let item: JSON = [
            "deeply": [
                "nested": [
                    "ints": [1, 2, 3],
                ],
            ],
        ]
        let context = Compute.Context(item: item)

        try await expect(["{returns}": ["item": []]], in: context, equals: item)
        try await expect(["{returns}": ["item": ["deeply", "nested", "ints"]]], in: context, equals: [1, 2, 3])
        try await expect(["{returns}": ["item": ["missing"]]], in: context, equals: nil)
    }

    @Test func supportsIndexedPathComponents() async throws {
        let context = Compute.Context(item: ["rectangle": [1, 2, 3, 4]])

        try await expect(["{returns}": ["item": ["rectangle", 0]]], in: context, equals: 1)
        try await expect(["{returns}": ["item": ["rectangle", 3]]], in: context, equals: 4)
    }

    @Test func readsValuesFromTaskLocalContext() async throws {
        let runtime = ComputeRuntime(document: ["{returns}": ["item": ["name"]]])

        let values = try await Compute.withContext { context in
            context.item = users[1]
        } operation: {
            let runtimeValue = try await runtime.value()
            let contextItem = try await taskLocalItem()
            return (runtimeValue, contextItem)
        }

        #expect(values.0 == "Noah")
        #expect(values.1 == users[1])
    }

    @Test func composesInsidePredicates() async throws {
        try await expectNames(
            matching: [
                "{returns}": [
                    "comparison": [
                        "greater_or_equal": [
                            "lhs": ["{returns}": ["item": ["age"]]],
                            "rhs": 36,
                        ],
                    ],
                ],
            ],
            ["Noah", "Ste"]
        )
    }
}

private func taskLocalItem() async throws -> JSON? {
    @Compute.Context var context
    return context.item
}
