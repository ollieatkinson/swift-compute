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

    @Test func brainPrintChangesLogsThoughtsAndStateDiffs() async throws {
        let logs = ChangeLogProbe()
        let brain = Brain<String, JSON>(
            [
                .init("count", inputs: ["input"]),
            ],
            state: ["input": 0],
            change: ["input": 1],
            remainingThoughts: { state in
                state["count"] == 1 ? 0 : 1
            }
        )
        var states = brain._printChanges { await logs.append($0) }.makeAsyncIterator()

        #expect(await states.next() == ["input": 0])
        try await brain.commit { lemma, state in
            #expect(lemma == "count")
            return state["input"]
        }
        #expect(await states.next()?["count"] == 1)

        let messages = await logs.messages
        #expect(messages == [
            """
            🧠._printChanges
              state:
                [
                  "input": .int(0)
                ]
            """,
            """
            🧠._printChanges
              thoughts:
                [
                  "count": .int(1)
                ]
              state diff:
                  [
                +   "count": .int(1),
                -   "input": .int(0)
                +   "input": .int(1)
                  ]
            """,
        ])

        await brain.cancelStreams()
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
