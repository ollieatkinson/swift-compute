import Foundation
import Compute
import Testing

@Suite(.serialized)
struct ComputeRuntimeEdgeCaseTests {

    @Test func value_settles_all_ready_computes_at_the_deepest_depth_in_one_wave() async throws {
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

    @Test func concurrent_steps_are_serialized_through_the_brain() async throws {
        let runtime = try runtime([
            "left": ["{returns}": ["comparison": ["equal": ["lhs": 1, "rhs": 1]]]],
            "right": ["{returns}": ["comparison": ["equal": ["lhs": 1, "rhs": 2]]]],
        ])

        async let first = runtime.step()
        async let second = runtime.step()
        let steps = try await [first, second]
        let routes = steps.flatMap { $0.thoughts.map(\.route) }

        #expect(Set(routes) == Set<Compute.Route>([["left"], ["right"]]))
        #expect(steps.map(\.remainingThoughts).sorted() == [0, 0])
        #expect(try await runtime.value() == [
            "left": true,
            "right": false,
        ])
    }

    @Test func malformed_function_payloads_throw_json_errors() async throws {
        await expectJSONError(containing: "Expected a [Any]") {
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

    @Test func deeply_nested_synchronous_documents_do_not_hit_the_recursion_limit() async throws {
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

        #expect(try await runtime(document).value() == true)
    }

    @Test func async_returned_compute_loops_hit_the_recursion_limit() async throws {
        let references = TestReferences()
        await references.set("loop", to: ["{returns}": ["from": ["reference": "loop"]]])

        await expectJSONError(containing: "recursionLimitExceeded") {
            _ = try await runtime(
                ["{returns}": ["from": ["reference": "loop"]]],
                references: references
            ).value()
        }

        await references.finish()
    }

    @Test func generated_compute_loops_hit_the_recursion_limit() async throws {
        let loop = GeneratedLoopFunction()

        await expectJSONError(containing: "recursionLimitExceeded") {
            _ = try await runtime(
                ["{returns}": ["loop": .object([:])]],
                functions: [loop]
            ).value()
        }
    }

    @Test func custom_async_returns_keywords_can_stream_updates() async throws {
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
            functions: [flag.function(name: "flag")]
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

    nonisolated func function(name: String) -> Function {
        Function(name: name, probe: self)
    }

    fileprivate func value() -> JSON {
        current
    }

    fileprivate nonisolated func values(
        bufferingPolicy: Compute.ReturnsKeywordDefinition.BufferingPolicy
    ) -> AsyncStream<Result<JSON, JSONError>> {
        AsyncStream(bufferingPolicy: bufferingPolicy) { continuation in
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

    struct Function: Compute.ReturnsKeywordDefinition {
        let name: String
        let probe: AsyncReturnsProbe

        func compute(data input: JSON, frame: Compute.Frame) async throws -> JSON? {
            await probe.value()
        }

        func subject(
            data input: JSON,
            frame: Compute.Frame,
            bufferingPolicy: Compute.ReturnsKeywordDefinition.BufferingPolicy
        ) -> AsyncStream<Result<JSON, JSONError>> {
            probe.values(bufferingPolicy: bufferingPolicy)
        }
    }
}

private struct GeneratedLoopFunction: AnyReturnsKeyword {
    let name = "loop"

    func compute(data input: JSON, frame: Compute.Frame) async throws -> JSON? {
        ["{returns}": ["loop": .object([:])]]
    }
}
