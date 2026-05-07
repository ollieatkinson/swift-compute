import Compute
import Testing

@Suite(.serialized)
struct CountTests {

    @Test func counts_primitive_collections_and_missing_values() async throws {
        try await expect(["{returns}": ["count": ["of": [1, 2, 3]]]], equals: 3)
        try await expect(["{returns}": ["count": ["of": ["a": 1, "b": 2]]]], equals: 2)
        try await expect(["{returns}": ["count": ["of": "Hello World!"]]], equals: 12)
        try await expect(["{returns}": ["count": ["of": nil]]], equals: 0)
    }

    @Test func counts_referenced_values_and_treats_missing_references_as_empty() async throws {
        let references = TestReferences()
        await references.set("data.type.string", to: "Hello World!")

        #expect(try await runtime(
            [
                "{returns}": [
                    "count": [
                        "of": ["{returns}": ["from": ["reference": "data.type.string"]]],
                    ],
                ],
            ],
            references: references
        ).value() == 12)
        #expect(try await runtime(
            [
                "{returns}": [
                    "count": [
                        "of": ["{returns}": ["from": ["reference": "data.type.missing"]]],
                    ],
                ],
            ],
            references: references
        ).value() == 0)

        await references.finish()
    }

    @Test func reacts_to_reference_changes() async throws {
        let references = TestReferences()
        await references.set("items", to: [1, 2])
        let json: JSON = [
            "{returns}": [
                "count": [
                    "of": ["{returns}": ["from": ["reference": "items"]]],
                ],
            ],
        ]
        let runtime = try runtime(json, references: references)
        var stream = runtime.run().makeAsyncIterator()

        await expectNext(&stream, equals: .success(2))
        await references.set("items", to: [1, 2, 3])
        await expectNext(&stream, equals: .success(3))

        await references.finish()
        await runtime.cancel()
    }
}
