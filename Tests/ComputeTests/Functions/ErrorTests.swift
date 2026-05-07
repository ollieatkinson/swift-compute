import Testing

@Suite(.serialized)
struct ErrorKeywordTests {

    @Test func throws_resolved_messages() async {
        await expectJSONError(containing: "boom") {
            _ = try await value(["{returns}": ["error": ["message": "boom"]]])
        }
        await expectJSONError(containing: "computed boom") {
            _ = try await value([
                "{returns}": [
                    "error": [
                        "message": ["{returns}": ["this": ["value": "computed boom"]]],
                    ],
                ],
            ])
        }
    }
}
