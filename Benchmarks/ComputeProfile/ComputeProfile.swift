import Compute
import Dispatch
import Foundation

@main
enum ComputeProfileMain {
    static func main() async {
        let iterations = iterationCount()
        let referenceFanout = ReferenceFanoutRunner()
        await run("reference_fanout", iterations: iterations) { _ in
            await referenceFanout.runOnce()
        }
        let arrayFilter = ArrayFilterRunner()
        await run("array_filter_512", iterations: iterations) { _ in
            await arrayFilter.runOnce()
        }
        let arrayMap = ArrayMapRunner()
        await run("array_map_512", iterations: iterations) { _ in
            await arrayMap.runOnce()
        }
        let reactiveUpdates = await ReactiveUpdatesRunner()
        await run("reactive_updates", iterations: iterations) { iteration in
            await reactiveUpdates.runOnce(iteration: iteration)
        }
        await reactiveUpdates.cancel()
    }

    @MainActor
    private static func run(
        _ name: String,
        iterations: Int,
        operation: (Int) async -> Int
    ) async {
        ComputeProfiling.reset()
        ComputeProfiling.setEnabled(true)
        let start = DispatchTime.now().uptimeNanoseconds
        var checksum = 0
        for iteration in 0..<iterations {
            checksum &+= await operation(iteration)
        }
        let elapsed = DispatchTime.now().uptimeNanoseconds - start
        ComputeProfiling.setEnabled(false)

        print("")
        print("== \(name) ==")
        print("iterations\t\(iterations)")
        print("elapsed_us\t\(String(format: "%.3f", Double(elapsed) / 1_000))")
        print("checksum\t\(checksum)")
        print(ComputeProfiling.snapshot())
    }

    private static func iterationCount() -> Int {
        guard let index = CommandLine.arguments.firstIndex(of: "--iterations"),
              CommandLine.arguments.indices.contains(index + 1),
              let value = Int(CommandLine.arguments[index + 1]),
              value > 0 else {
            return 100
        }
        return value
    }
}

private struct ReferenceFanoutRunner: Sendable {
    let document: JSON
    let functions: [any AnyReturnsKeyword]

    init() {
        let conditionCount = 48
        var referenceValues: [String: JSON] = [:]
        let conditions: [JSON] = (0..<conditionCount).map { index in
            referenceValues["metric.\(index)"] = .int(index + 100)
            return .returns("comparison", [
                "greater_or_equal": [
                    "lhs": JSON.returns("from", ["reference": .string("metric.\(index)")]),
                    "rhs": .int(index),
                ],
            ])
        }
        document = .returns("yes", ["if": .array(conditions)])
        functions = [From.Function(references: StaticReferences(referenceValues))]
    }

    func runOnce() async -> Int {
        let runtime = ComputeRuntime(document: document, functions: functions)
        let value = await runtimeValue(runtime)
        guard value == .bool(true) else {
            fatalError("reference_fanout produced \(value)")
        }
        return 1
    }
}

private struct ArrayFilterRunner: Sendable {
    let document: JSON
    let expectedCount: Int

    init() {
        let users = makeUsers(count: 512)
        expectedCount = users.filter { user in
            let age = intValue(user, key: "age")
            let score = intValue(user, key: "score")
            return age >= 35 && score < 75
        }.count
        document = JSON.returns("array_filter", [
            "array": .array(users),
            "predicate": JSON.returns("yes", [
                "if": [
                    JSON.returns("comparison", [
                        "greater_or_equal": [
                            "lhs": JSON.returns("item", ["age"]),
                            "rhs": 35,
                        ],
                    ]),
                    JSON.returns("comparison", [
                        "less": [
                            "lhs": JSON.returns("item", ["score"]),
                            "rhs": 75,
                        ],
                    ]),
                ],
            ]),
        ])
    }

    func runOnce() async -> Int {
        let runtime = ComputeRuntime(document: document)
        let value = await runtimeValue(runtime)
        guard case .array(let filtered) = value, filtered.count == expectedCount else {
            fatalError("array_filter_512 produced \(value)")
        }
        return filtered.count
    }
}

private struct ArrayMapRunner: Sendable {
    let document: JSON
    let expectedCount: Int

    init() {
        let users = makeUsers(count: 512)
        expectedCount = users.count
        document = JSON.returns("array_map", [
            "over": .array(users),
            "into_self": true,
            "copy": [
                [
                    "value": JSON.returns("item", ["age"]),
                    "to": ["analytics", "age"],
                ],
                [
                    "value": JSON.returns("comparison", [
                        "greater_or_equal": [
                            "lhs": JSON.returns("item", ["score"]),
                            "rhs": 50,
                        ],
                    ]),
                    "to": ["analytics", "highScore"],
                ],
            ],
        ])
    }

    func runOnce() async -> Int {
        let runtime = ComputeRuntime(document: document)
        let value = await runtimeValue(runtime)
        guard case .array(let mapped) = value, mapped.count == expectedCount else {
            fatalError("array_map_512 produced \(value)")
        }
        var checksum = mapped.count
        if let first = mapped.first {
            checksum &+= analyticsAge(first)
        }
        return checksum
    }
}

private final class ReactiveUpdatesRunner: @unchecked Sendable {
    let references: UpdatingReferences
    let runtime: ComputeRuntime
    var iterator: AsyncStream<Result<JSON, JSONError>>.Iterator

    init() async {
        let document = JSON.returns("yes", [
            "if": JSON.returns("comparison", [
                "greater_or_equal": [
                    "lhs": JSON.returns("from", ["reference": "age"]),
                    "rhs": 18,
                ],
            ]),
        ])
        let references = UpdatingReferences()
        await references.set("age", to: 20)
        let runtime = ComputeRuntime(
            document: document,
            functions: [From.Function(references: references)]
        )
        var iterator = runtime.run().makeAsyncIterator()
        guard await nextValue(from: &iterator) == .bool(true) else {
            fatalError("reactive_updates did not publish the initial value")
        }
        self.references = references
        self.runtime = runtime
        self.iterator = iterator
    }

    func runOnce(iteration: Int) async -> Int {
        let nextAge = iteration.isMultiple(of: 2) ? 17 : 20
        let expected = !iteration.isMultiple(of: 2)
        await references.set("age", to: .int(nextAge))
        guard let result = await iterator.next() else {
            fatalError("stream ended")
        }
        let value: JSON
        do {
            value = try result.get()
        } catch {
            fatalError("stream produced \(error)")
        }
        guard value == .bool(expected) else {
            fatalError("reactive_updates produced \(value), expected \(expected)")
        }
        return expected ? 1 : 2
    }

    func cancel() async {
        await runtime.cancel()
    }
}

private struct StaticReferences: ComputeReferences {
    let values: [String: JSON]

    init(_ values: [String: JSON]) {
        self.values = values
    }

    func value(for reference: JSON, context: [String: JSON]?) async throws -> JSON {
        guard case .string(let key) = reference, let value = values[key] else {
            throw ComputeError.unresolvedReference(reference)
        }
        return value
    }
}

private actor UpdatingReferences: AsyncComputeReferences {
    private var values: [String: JSON] = [:]
    private var continuations: [String: [UUID: AsyncStream<Result<JSON, JSONError>>.Continuation]] = [:]

    func set(_ reference: String, to value: JSON) {
        values[reference] = value
        publish(.success(value), for: reference)
    }

    func value(for reference: JSON, context: [String: JSON]?) async throws -> JSON {
        let key = try key(for: reference)
        guard let value = values[key] else {
            throw ComputeError.unresolvedReference(reference)
        }
        return value
    }

    nonisolated func values(
        for reference: JSON,
        context: [String: JSON]?
    ) -> AsyncStream<Result<JSON, JSONError>> {
        AsyncStream { continuation in
            let id = UUID()
            let task = Task {
                do {
                    let key = try self.key(for: reference)
                    await self.addContinuation(continuation, id: id, for: key)
                } catch {
                    continuation.yield(.failure(JSONError(error)))
                    continuation.finish()
                }
            }
            continuation.onTermination = { @Sendable [weak self] _ in
                task.cancel()
                Task { [weak self] in
                    guard let self, let key = try? self.key(for: reference) else { return }
                    await self.removeContinuation(id: id, for: key)
                }
            }
        }
    }

    private func addContinuation(
        _ continuation: AsyncStream<Result<JSON, JSONError>>.Continuation,
        id: UUID,
        for key: String
    ) {
        continuations[key, default: [:]][id] = continuation
        if let value = values[key] {
            continuation.yield(.success(value))
        }
    }

    private func removeContinuation(id: UUID, for key: String) {
        continuations[key]?[id] = nil
    }

    private func publish(_ result: Result<JSON, JSONError>, for key: String) {
        guard let continuations = continuations[key]?.values else { return }
        for continuation in continuations {
            continuation.yield(result)
        }
    }

    private nonisolated func key(for reference: JSON) throws -> String {
        guard case .string(let key) = reference else {
            throw ComputeError.unresolvedReference(reference)
        }
        return key
    }
}

private func nextValue(
    from iterator: inout AsyncStream<Result<JSON, JSONError>>.Iterator
) async -> JSON {
    guard let result = await iterator.next() else {
        fatalError("stream ended")
    }
    do {
        return try result.get()
    } catch {
        fatalError("stream produced \(error)")
    }
}

private func runtimeValue(_ runtime: ComputeRuntime) async -> JSON {
    do {
        return try await runtime.value()
    } catch {
        fatalError("runtime failed with \(error)")
    }
}

private func makeUsers(count: Int) -> [JSON] {
    (0..<count).map { index in
        [
            "id": .int(index),
            "name": .string("user-\(index)"),
            "age": .int(18 + (index % 60)),
            "score": .int((index * 37) % 100),
            "tags": [
                .string("group-\(index % 8)"),
                .string(index.isMultiple(of: 2) ? "even" : "odd"),
            ],
        ]
    }
}

private func intValue(_ json: JSON, key: String) -> Int {
    guard case .object(let object) = json, case .int(let value)? = object[key] else {
        preconditionFailure("Expected integer key \(key)")
    }
    return value
}

private func analyticsAge(_ json: JSON) -> Int {
    guard case .object(let object) = json,
          case .object(let analytics)? = object["analytics"],
          case .int(let value)? = analytics["age"] else {
        preconditionFailure("Expected analytics.age")
    }
    return value
}
