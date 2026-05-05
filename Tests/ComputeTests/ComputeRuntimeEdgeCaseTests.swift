import Foundation
import Compute
import Testing

@Suite(.serialized)
struct ComputeRuntimeEdgeCaseTests {

    @Test func valueSettlesAllReadyComputesAtTheDeepestDepthInOneWave() async throws {
        let runtime = try runtime([
            "left": ["{returns}": ["comparison": ["equal": ["lhs": 1, "rhs": 1]]]],
            "right": ["{returns}": ["comparison": ["equal": ["lhs": 1, "rhs": 2]]]],
        ])

        #expect(try await runtime.value() == [
            "left": true,
            "right": false,
        ])
        #expect(await runtime.thoughts.map(\.route) == [["left"], ["right"]])
        #expect(await runtime.thoughts.map(\.output) == [true, false])
    }

    @Test func concurrentStepsAreSerializedThroughTheBrain() async throws {
        let runtime = try runtime([
            "left": ["{returns}": ["comparison": ["equal": ["lhs": 1, "rhs": 1]]]],
            "right": ["{returns}": ["comparison": ["equal": ["lhs": 1, "rhs": 2]]]],
        ])

        async let first = runtime.step()
        async let second = runtime.step()
        let steps = try await [first, second]
        let routes = steps.flatMap { $0.thoughts.map(\.route) }

        #expect(Set(routes) == Set<ComputeRoute>([["left"], ["right"]]))
        #expect(steps.map(\.remainingThoughts).sorted() == [0, 0])
        #expect(try await runtime.value() == [
            "left": true,
            "right": false,
        ])
    }

    @Test func malformedFunctionPayloadsThrowJSONErrors() async throws {
        await expectJSONError(containing: "array_filter expected an array") {
            _ = try await runtime([
                "{returns}": [
                    "array_filter": [
                        "array": "not an array",
                        "predicate": true,
                    ],
                ],
            ]).value()
        }

        await expectJSONError(containing: "Value of type Bool not found") {
            _ = try await runtime([
                "{returns}": [
                    "array_filter": [
                        "array": [1, 2, 3],
                        "predicate": [true],
                    ],
                ],
            ]).value()
        }
    }

    @Test func deeplyNestedResolvedDocumentsHitTheRecursionLimit() async throws {
        await expectJSONError(containing: "recursionLimitExceeded") {
            var document: JSON = true
            for _ in 0..<25 {
                document = [
                    "{returns}": [
                        "this": [
                            "value": document,
                        ],
                    ],
                ]
            }
            _ = try await runtime(document).value()
        }
    }

    @Test func customAsyncReturnsKeywordsCanStreamUpdates() async throws {
        let flag = AsyncReturnsProbe(false)
        let runtime = try runtime(
            [
                "{returns}": [
                    "not": [
                        "{returns}": [
                            "flag": "feature.enabled",
                        ],
                    ],
                ],
            ],
            functions: [flag.function(keyword: "flag")]
        )
        var stream = runtime.run().makeAsyncIterator()

        await expectNext(&stream, equals: .success(true))
        await flag.set(true)
        await expectNext(&stream, equals: .success(false))
        await flag.set(false)
        await expectNext(&stream, equals: .success(true))

        await flag.finish()
        await runtime.cancel()
    }
}

private actor AsyncReturnsProbe {
    private var current: JSON
    private var continuations: [UUID: AsyncStream<Result<JSON, JSONError>>.Continuation] = [:]

    init(_ current: JSON) {
        self.current = current
    }

    func set(_ value: JSON) {
        current = value
        for continuation in continuations.values {
            continuation.yield(.success(value))
        }
    }

    func finish() {
        for continuation in continuations.values {
            continuation.finish()
        }
        continuations.removeAll()
    }

    nonisolated func function(keyword: String) -> AnyReturnsFunction {
        AnyReturnsFunction(
            keyword: keyword,
            value: { [self] _ in await self.value() },
            values: { [self] _ in self.values() }
        )
    }

    private func value() -> JSON {
        current
    }

    private nonisolated func values() -> AsyncStream<Result<JSON, JSONError>> {
        AsyncStream { continuation in
            let id = UUID()
            let task = Task { [self] in
                await self.add(continuation, id: id)
            }
            continuation.onTermination = { @Sendable [self] _ in
                task.cancel()
                Task {
                    await self.remove(id: id)
                }
            }
        }
    }

    private func add(
        _ continuation: AsyncStream<Result<JSON, JSONError>>.Continuation,
        id: UUID
    ) {
        continuations[id] = continuation
        continuation.yield(.success(current))
    }

    private func remove(id: UUID) {
        continuations[id] = nil
    }
}

private func expectJSONError(
    containing fragment: String,
    sourceLocation: SourceLocation = #_sourceLocation,
    _ operation: () async throws -> Void
) async {
    do {
        try await operation()
        Issue.record("Expected JSONError containing \(fragment)", sourceLocation: sourceLocation)
    } catch let error as JSONError {
        #expect(error.description.contains(fragment), sourceLocation: sourceLocation)
    } catch {
        Issue.record("Expected JSONError, got \(error)", sourceLocation: sourceLocation)
    }
}
