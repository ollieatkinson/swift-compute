import Brain
import Testing

@Suite(.serialized)
struct BrainTests {
    @Test func commitsBoundedThoughtsUntilSettled() async throws {
        let brain = Brain<String, Int>(
            [
                .init("adult", inputs: ["age"]),
            ],
            state: ["age": 17],
            change: ["age": 21],
            remainingThoughts: { state in
                state["adult"] == 1 ? 0 : 1
            }
        )

        let commit = try await brain.commit(thoughts: 1) { lemma, state in
            #expect(lemma == "adult")
            #expect(state["age"] == 21)
            return 1
        }

        #expect(commit.change == ["age": 21])
        #expect(commit.thoughts == ["adult": 1])
        #expect(commit.state["adult"] == 1)
        #expect(commit.remainingThoughts == 0)
        #expect(commit.isThinking == false)
        #expect(await brain.value["adult"] == 1)
        await brain.cancelStreams()
    }
}
