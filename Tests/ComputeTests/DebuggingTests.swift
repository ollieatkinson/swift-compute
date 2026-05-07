import Compute
import Testing

@Suite(.serialized)
struct DebuggingTests {
    @Test func computeRuntimePrintChangesLogsEventsThoughtsAndStateDiffs() async throws {
        let references = TestReferences()
        await references.set("minimum_age", to: 38)
        let json: JSON = [
            "{returns}": [
                "comparison": [
                    "greater_or_equal": [
                        "lhs": ["{returns}": ["item": ["age"]]],
                        "rhs": ["{returns}": ["from": ["reference": "minimum_age"]]],
                    ],
                ],
            ],
        ]
        let logs = ChangeLogProbe()
        let runtime = try runtime(json, in: Compute.Context(item: users[2]), references: references)
        var stream = runtime._printChanges { await logs.append($0) }.makeAsyncIterator()

        await expectNext(&stream, equals: .success(false))
        await references.set("minimum_age", to: 36)
        await expectNext(&stream, equals: .success(true))

        let messages = await logs.messages
        #expect(messages == [
            """
            ⏳._printChanges
              route: /
              event: ✅ success
              thoughts:
                [0] compute item @ {returns}.comparison.greater_or_equal.lhs -> 36
                [1] returns from @ {returns}.comparison.greater_or_equal.rhs -> 38
                [2] compute comparison @ / -> false
              state:
                JSON.bool(false)
            """,
            """
            ⏳._printChanges
              route: /
              event: ✅ success
              thoughts:
                [0] returns from @ {returns}.comparison.greater_or_equal.rhs -> 36
                [1] compute comparison @ / -> true
              state diff:
                - JSON.bool(false)
                + JSON.bool(true)
            """,
        ])

        await references.finish()
        await runtime.cancel()
    }
}

private actor ChangeLogProbe {
    private var loggedMessages: [String] = []

    var messages: [String] {
        loggedMessages
    }

    func append(_ message: String) {
        loggedMessages.append(message)
    }
}
