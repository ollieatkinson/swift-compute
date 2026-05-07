import Brain
import Testing

@Suite(.serialized)
struct DebuggingTests {
    @Test func print_changes_logs_thoughts_and_state_diffs() async throws {
        let logs = ChangeLogProbe()
        let brain = Brain<String, Int>(
            [
                .init("count", inputs: ["input"]),
            ],
            state: ["input": 0],
            change: ["input": 1],
            remainingThoughts: { state in
                state["count"] == 1 ? 0 : 1
            }
        )
        var states = brain._printChanges("brain") { await logs.append($0) }.makeAsyncIterator()

        #expect(await states.next() == ["input": 0])
        try await brain.commit { lemma, state in
            #expect(lemma == "count")
            return state["input"]
        }
        #expect(await states.next()?["count"] == 1)

        let messages = await logs.messages
        #expect(messages.count == 2)
        #expect(messages.first?.contains("brain._printChanges") == true)
        #expect(messages.first?.contains("state:") == true)
        #expect(messages.last?.contains("thoughts:") == true)
        #expect(messages.last?.contains("state diff:") == true)

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
