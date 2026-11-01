import Brain
import Testing

@Suite struct BrainCancellationTests {
    @Test(arguments: [false, true])
    func cancelled_evaluations_preserve_pending_changes_and_do_not_reset_the_graph(reset: Bool) async throws {
        let concepts: [Brain<String, Int>.Concept] = [.init("output", inputs: ["input"])]
        let brain = Brain(concepts, state: ["input": 1], change: ["input": 2],
            remainingThoughts: { _ in 0 })
        let cancelled = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            let thinking: Brain<String, Int>.Thinking = { _, _ in
                Issue.record("A cancelled evaluation must not start thinking")
                return 100
            }
            if reset {
                return try await brain.settle(resetTo: ["input": 99], concepts: [],
                    staging: ["input": 100], thinking: thinking)
            }
            return try await brain.commit(thinking: thinking)
        }
        do {
            _ = try await cancelled.value
            Issue.record("Expected cancellation")
        } catch is CancellationError {} catch { Issue.record(error) }
        #expect(await brain.value == ["input": 1])

        let resumed = try await brain.settle { _, state in state["input"] }
        #expect(resumed.change == ["input": 2])
        #expect(resumed.state == ["input": 2, "output": 2])
        await brain.cancelStreams()
    }
}
