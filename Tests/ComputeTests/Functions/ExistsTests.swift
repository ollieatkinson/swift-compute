import Compute
import Testing

@Suite(.serialized)
struct ExistsTests {

    @Test func evaluatesResolvedValuesAndMissingValues() async throws {
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

    @Test func reactsToReferenceChanges() async throws {
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
