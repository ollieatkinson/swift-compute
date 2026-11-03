import Compute
import Testing

@Suite(.timeLimit(.minutes(1)))
struct ComputeRuntimeConcurrentTraceTests {
    @Test
    func overlapping_explanations_capture_only_their_own_branch() async throws {
        let references = TestReferences(initiallyPending: true)
        let runtime = try runtime([
            "left": .returns("explain", ["value": .returns("from", ["reference": "left"])]),
            "right": .returns("explain", ["value": .returns("from", ["reference": "right"])])
        ], references: references)
        defer { await runtime.cancel() }
        var rights = runtime.run(at: ["right"]).makeAsyncIterator()
        var documents = runtime.run().makeAsyncIterator()
        try await wait {
            let left = await references.subscriptionCount(for: "left")
            let right = await references.subscriptionCount(for: "right")
            return left == 1 && right == 1
        }
        await references.set("right", to: "Right")
        let right = try #require(await rights.next()).get()
        #expect(right.object?["value"] == "Right")
        let rightThoughts = try #require(right["thoughts"].array)
        #expect(!rightThoughts.isEmpty)
        #expect(rightThoughts.allSatisfy { $0["route"].array?.first == "right" })
        await references.set("left", to: "Left")
        let document = try #require(await documents.next()).get()
        #expect(document.object?["left"]?.object?["value"] == "Left")
        let leftThoughts = try #require(document["left"]["thoughts"].array)
        #expect(!leftThoughts.isEmpty)
        #expect(leftThoughts.allSatisfy { $0["route"].array?.first == "left" })
    }

    @Test
    func detached_frame_work_and_explicit_routes_stay_in_the_explanation() async throws {
        let operation = DetachedRecording()
        let explained = try await value(
            .returns("explain", ["value": .returns(operation.name, [:])]),
            functions: [operation]
        )
        #expect(explained["value"] == 42)
        let thoughts = try #require(explained["thoughts"].array)
        #expect(thoughts.contains {
            $0.object?["keyword"] == "literal" && $0.object?["route"] == ["outside"]
        })
        #expect(thoughts.contains {
            $0.object?["keyword"] == "recorded" && $0.object?["route"] == ["external"]
        })
    }

    @Test
    func nested_explanations_keep_the_outer_capture_without_recording_themselves() async throws {
        let outer = try await value(.returns("explain", ["value": .returns("explain", [
            "value": .returns("literal", ["value": 42])
        ])]))
        let inner = try #require(outer.object?["value"])
        #expect(inner.object?["value"] == 42)
        let outerThoughts = try #require(outer["thoughts"].array)
        let innerThoughts = try #require(inner["thoughts"].array)
        #expect(outerThoughts.contains { $0.object?["keyword"] == "explain" })
        #expect(outerThoughts.contains { $0.object?["keyword"] == "literal" })
        #expect(innerThoughts.contains { $0.object?["keyword"] == "literal" })
        #expect(!innerThoughts.contains { $0.object?["keyword"] == "explain" })
    }

    private func wait(_ condition: @Sendable () async -> Bool) async throws {
        while !(await condition()) {
            try Task.checkCancellation()
            await Task.yield()
        }
    }

    private struct DetachedRecording: Compute.OpaqueOutputKeyword {
        let name = "detached_recording"

        func compute(data: JSON, frame: Compute.Frame) async throws -> JSON? {
            let frame = frame.scoped(to: ["scope": "nested"])["child"]
            return try await Task.detached {
                let result = try await frame.compute(
                    .returns("literal", ["value": 42]),
                    at: ["outside"]
                )
                await frame.record(Compute.Thought(
                    route: ["external"],
                    depth: 0,
                    keyword: "recorded",
                    output: result
                ))
                return result
            }.value
        }
    }
}
