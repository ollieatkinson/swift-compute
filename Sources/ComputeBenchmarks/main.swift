import Compute
import Foundation

private struct BenchmarkError: Error, CustomStringConvertible {
    let description: String

    init(_ description: String) {
        self.description = description
    }
}

private protocol BenchmarkRunner: Sendable {
    func run(iterations: Int) async -> Int
}

private struct BenchmarkCase {
    let name: String
    let iterations: Int
    let warmupIterations: Int
    let runner: any BenchmarkRunner
}

private struct BenchmarkResult {
    let name: String
    let iterations: Int
    let samples: [Double]
    let checksum: Int

    var medianMicroseconds: Double {
        let sorted = samples.sorted()
        let middle = sorted.count / 2
        if sorted.count.isMultiple(of: 2) {
            return (sorted[middle - 1] + sorted[middle]) / 2
        }
        return sorted[middle]
    }

    var operationsPerSecond: Double {
        1_000_000 / medianMicroseconds
    }
}

private struct BenchmarkOptions {
    var quick = false
    var samples = 5

    init(arguments: [String]) throws {
        var index = 1
        while index < arguments.count {
            switch arguments[index] {
            case "--quick":
                quick = true
                index += 1
            case "--samples":
                guard index + 1 < arguments.count, let value = Int(arguments[index + 1]), value > 0 else {
                    throw BenchmarkError("Expected a positive integer after --samples")
                }
                samples = value
                index += 2
            case "--help", "-h":
                print("""
                Usage: swift run -c release ComputeBenchmarks [--quick] [--samples N]

                Prints a lower-is-better geometric mean score and per-scenario timings.
                """)
                Foundation.exit(0)
            default:
                throw BenchmarkError("Unknown argument \(arguments[index])")
            }
        }
    }
}

@main
private enum ComputeBenchmarks {
    static func main() async throws {
        let options = try BenchmarkOptions(arguments: CommandLine.arguments)
        let scale = options.quick ? 0.2 : 1.0
        let cases = [
            referenceFanoutCase(scale: scale),
            arrayFilterCase(scale: scale),
            arrayMapCase(scale: scale),
            reactiveUpdatesCase(scale: scale),
        ]

        var results: [BenchmarkResult] = []
        let suiteStart = DispatchTime.now().uptimeNanoseconds
        for benchmark in cases {
            results.append(await measure(benchmark, samples: options.samples))
        }
        let suiteSeconds = Double(DispatchTime.now().uptimeNanoseconds - suiteStart) / 1_000_000_000
        let score = geometricMean(results.map(\.medianMicroseconds))

        print("---")
        print("score_us:          \(format(score, digits: 3))")
        print("total_seconds:     \(format(suiteSeconds, digits: 3))")
        print("samples:           \(options.samples)")
        for result in results {
            print(
                "\(result.name): median_us=\(format(result.medianMicroseconds, digits: 3)) " +
                "ops_s=\(format(result.operationsPerSecond, digits: 1)) " +
                "iterations=\(result.iterations) checksum=\(result.checksum)"
            )
        }
    }

    private static func measure(_ benchmark: BenchmarkCase, samples: Int) async -> BenchmarkResult {
        _ = await benchmark.runner.run(iterations: benchmark.warmupIterations)
        var sampleMicroseconds: [Double] = []
        var checksum = 0
        for _ in 0..<samples {
            let start = DispatchTime.now().uptimeNanoseconds
            checksum &+= await benchmark.runner.run(iterations: benchmark.iterations)
            let elapsed = DispatchTime.now().uptimeNanoseconds - start
            sampleMicroseconds.append(Double(elapsed) / Double(benchmark.iterations) / 1_000)
        }
        return BenchmarkResult(
            name: benchmark.name,
            iterations: benchmark.iterations,
            samples: sampleMicroseconds,
            checksum: checksum
        )
    }
}

private func referenceFanoutCase(scale: Double) -> BenchmarkCase {
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
    let document = JSON.returns("yes", ["if": .array(conditions)])
    let references = StaticReferences(referenceValues)
    let functions: [any AnyReturnsKeyword] = [From.Function(references: references)]
    let iterations = scaledIterations(220, scale: scale)

    return BenchmarkCase(
        name: "reference_fanout",
        iterations: iterations,
        warmupIterations: max(1, iterations / 5),
        runner: ReferenceFanoutRunner(document: document, functions: functions)
    )
}

private func arrayFilterCase(scale: Double) -> BenchmarkCase {
    let users = makeUsers(count: 512)
    let expectedCount = users.filter { user in
        let age = intValue(user, key: "age")
        let score = intValue(user, key: "score")
        return age >= 35 && score < 75
    }.count
    let document = JSON.returns("array_filter", [
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
    let iterations = scaledIterations(70, scale: scale)

    return BenchmarkCase(
        name: "array_filter_512",
        iterations: iterations,
        warmupIterations: max(1, iterations / 5),
        runner: ArrayFilterRunner(document: document, expectedCount: expectedCount)
    )
}

private func arrayMapCase(scale: Double) -> BenchmarkCase {
    let users = makeUsers(count: 512)
    let document = JSON.returns("array_map", [
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
    let iterations = scaledIterations(70, scale: scale)

    return BenchmarkCase(
        name: "array_map_512",
        iterations: iterations,
        warmupIterations: max(1, iterations / 5),
        runner: ArrayMapRunner(document: document, expectedCount: users.count)
    )
}

private func reactiveUpdatesCase(scale: Double) -> BenchmarkCase {
    let iterations = scaledIterations(260, scale: scale)
    let document = JSON.returns("yes", [
        "if": JSON.returns("comparison", [
            "greater_or_equal": [
                "lhs": JSON.returns("from", ["reference": "age"]),
                "rhs": 18,
            ],
        ]),
    ])

    return BenchmarkCase(
        name: "reactive_updates",
        iterations: iterations,
        warmupIterations: max(1, iterations / 5),
        runner: ReactiveUpdatesRunner(document: document)
    )
}

private struct ReferenceFanoutRunner: BenchmarkRunner {
    let document: JSON
    let functions: [any AnyReturnsKeyword]

    func run(iterations: Int) async -> Int {
        var checksum = 0
        for _ in 0..<iterations {
            let runtime = ComputeRuntime(document: document, functions: functions)
            let value = await runtimeValue(runtime)
            guard value == .bool(true) else {
                fatalError("reference_fanout produced \(value)")
            }
            checksum &+= 1
        }
        return checksum
    }
}

private struct ArrayFilterRunner: BenchmarkRunner {
    let document: JSON
    let expectedCount: Int

    func run(iterations: Int) async -> Int {
        var checksum = 0
        for _ in 0..<iterations {
            let runtime = ComputeRuntime(document: document)
            let value = await runtimeValue(runtime)
            guard case .array(let filtered) = value, filtered.count == expectedCount else {
                fatalError("array_filter_512 produced \(value)")
            }
            checksum &+= filtered.count
        }
        return checksum
    }
}

private struct ArrayMapRunner: BenchmarkRunner {
    let document: JSON
    let expectedCount: Int

    func run(iterations: Int) async -> Int {
        var checksum = 0
        for _ in 0..<iterations {
            let runtime = ComputeRuntime(document: document)
            let value = await runtimeValue(runtime)
            guard case .array(let mapped) = value, mapped.count == expectedCount else {
                fatalError("array_map_512 produced \(value)")
            }
            checksum &+= mapped.count
            if let first = mapped.first {
                checksum &+= analyticsAge(first)
            }
        }
        return checksum
    }
}

private struct ReactiveUpdatesRunner: BenchmarkRunner {
    let document: JSON

    func run(iterations: Int) async -> Int {
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

        var checksum = 0
        for index in 0..<iterations {
            let nextAge = index.isMultiple(of: 2) ? 17 : 20
            let expected = !index.isMultiple(of: 2)
            await references.set("age", to: .int(nextAge))
            let value = await nextValue(from: &iterator)
            guard value == .bool(expected) else {
                fatalError("reactive_updates produced \(value), expected \(expected)")
            }
            checksum &+= expected ? 1 : 2
        }
        await runtime.cancel()
        return checksum
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

private func scaledIterations(_ iterations: Int, scale: Double) -> Int {
    max(1, Int((Double(iterations) * scale).rounded()))
}

private func geometricMean(_ values: [Double]) -> Double {
    exp(values.map(log).reduce(0, +) / Double(values.count))
}

private func format(_ value: Double, digits: Int) -> String {
    String(format: "%.\(digits)f", value)
}
