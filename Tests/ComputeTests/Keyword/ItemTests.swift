import Compute
import Testing

@Suite(.serialized)
struct ItemTests {

    @Test func reads_values_from_local_context() async throws {
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

    @Test func supports_indexed_path_components() async throws {
        let context = Compute.Context(item: ["rectangle": [1, 2, 3, 4]])

        try await expect(["{returns}": ["item": ["rectangle", 0]]], in: context, equals: 1)
        try await expect(["{returns}": ["item": ["rectangle", 3]]], in: context, equals: 4)
    }

    @Test func reads_values_from_runtime_context() async throws {
        let runtime = Compute.Runtime(
            document: ["{returns}": ["item": ["name"]]],
            context: Compute.Context(item: users[1])
        )

        #expect(try await runtime.value() == "Noah")
    }

    @Test func composes_inside_predicates() async throws {
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
