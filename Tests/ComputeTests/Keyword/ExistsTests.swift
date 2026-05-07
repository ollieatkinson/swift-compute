import Compute
import Testing

@Suite(.serialized)
struct ExistsTests {

    @Test func evaluates_resolved_values_and_missing_values() async throws {
        try await expect([
            "{returns}": [
                "exists": [
                    "value": ["{returns}": ["item": ["name"]]],
                ],
            ],
        ], in: Compute.Context(item: users[0]), equals: true)
        try await expect([
            "{returns}": [
                "exists": [
                    "value": ["{returns}": ["item": ["missing"]]],
                ],
            ],
        ], in: Compute.Context(item: users[0]), equals: false)
    }

    @Test func reacts_to_reference_changes() async throws {
        let references = TestReferences()
        let runtime = try runtime([
            "{returns}": [
                "exists": [
                    "value": ["{returns}": ["from": ["reference": "profile"]]],
                ],
            ],
        ], references: references)
        var stream = runtime.run().makeAsyncIterator()

        await expectNext(&stream, equals: .success(false))
        await references.set("profile", to: ["name": "Oliver"])
        await expectNext(&stream, equals: .success(true))

        await references.finish()
        await runtime.cancel()
    }
}
