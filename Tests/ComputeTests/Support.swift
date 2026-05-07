import Foundation
import Compute
import Testing

struct Address: Decodable, Equatable, Sendable {
    let city: String
    let postcode: String
}

struct User: Decodable, Equatable, Sendable {
    let name: String
    let age: Int
    let weight: Double
    let isClearToFly: Bool
    let address: Address
}

let users: [JSON] = [
    [
        "address": [
            "city": "Belgrade",
            "postcode": "11000",
        ],
        "age": 32,
        "isClearToFly": true,
        "name": "Milos",
        "weight": 78.2,
    ],
    [
        "address": [
            "city": "London",
            "postcode": "E1",
        ],
        "age": 38,
        "isClearToFly": false,
        "name": "Noah",
        "weight": 82.1,
    ],
    [
        "address": [
            "city": "Manchester",
            "postcode": "M1",
        ],
        "age": 36,
        "isClearToFly": false,
        "name": "Ste",
        "weight": 85.8,
    ],
]

actor TestReferences: Compute.AsyncReferences {
    private var results: [String: Result<JSON, JSONError>] = [:]
    private var continuations: [String: [UUID: AsyncStream<Result<JSON, JSONError>>.Continuation]] = [:]

    func set(_ reference: String, to value: JSON) {
        results[reference] = .success(value)
        publish(.success(value), for: reference)
    }

    func fail(_ reference: String, with error: JSONError) {
        results[reference] = .failure(error)
        publish(.failure(error), for: reference)
    }

    func finish() {
        for continuations in continuations.values {
            for continuation in continuations.values {
                continuation.finish()
            }
        }
        continuations.removeAll()
    }

    func value(for reference: JSON, context: [String: JSON]?) async throws -> JSON {
        let key = try key(for: reference, context: context)
        guard let result = results[key] else {
            throw Compute.Error.unresolvedReference(reference)
        }
        return try result.get()
    }

    nonisolated func values(
        for reference: JSON,
        context: [String: JSON]?
    ) -> AsyncStream<Result<JSON, JSONError>> {
        AsyncStream { continuation in
            let id = UUID()
            let task = Task {
                do {
                    let key = try key(for: reference, context: context)
                    await addContinuation(continuation, id: id, for: key)
                } catch {
                    continuation.yield(.failure(JSONError(error)))
                    continuation.finish()
                }
            }
            continuation.onTermination = { @Sendable [weak self] _ in
                task.cancel()
                Task { [weak self] in
                    guard let self else { return }
                    guard let key = try? self.key(for: reference, context: context) else { return }
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
        if let result = results[key] {
            continuation.yield(result)
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

    private nonisolated func key(for reference: JSON, context: [String: JSON]?) throws -> String {
        guard case .string(let base) = reference else {
            throw Compute.Error.unresolvedReference(reference)
        }
        guard let context else {
            return base
        }
        let suffix = context.keys.sorted().map { key in
            "\(key)=\(fragment(context[key] ?? .null))"
        }.joined(separator: "&")
        return "\(base)?\(suffix)"
    }

    private nonisolated func fragment(_ value: JSON) -> String {
        switch value {
        case .null:
            return "null"
        case .bool(let value):
            return String(value)
        case .int(let value):
            return String(value)
        case .double(let value):
            return String(value)
        case .string(let value):
            return "\"\(value)\""
        case .array, .object:
            return String(describing: value)
        }
    }
}

struct Echo: Compute.KeywordDefinition {
    static let name = "echo"
    let payload: JSON

    init(_ payload: JSON) {
        self.payload = payload
    }

    init(from decoder: Decoder) throws {
        self.payload = try JSON(from: decoder)
    }

    func encode(to encoder: Encoder) throws {
        try payload.encode(to: encoder)
    }

    func compute(in frame: Compute.Frame) async throws -> JSON? {
        payload
    }
}

struct RouteProbeFunction: AnyReturnsKeyword {
    var name: String { "route_probe" }

    func compute(data input: JSON, frame: Compute.Frame) async throws -> JSON? {
        frameSummary(frame, input: input)
    }
}

func frameSummary(_ frame: Compute.Frame, input: JSON? = nil) -> JSON {
    frameSummary(
        route: frame.route.components,
        depth: frame.depth,
        item: frame.context.item,
        input: input
    )
}

func frameSummary(
    route: [Compute.Route.Component],
    depth: Int,
    item: JSON? = nil,
    input: JSON? = nil
) -> JSON {
    var summary: [String: JSON] = [
        "depth": .int(depth),
        "item": item ?? .null,
        "route": routeJSON(route),
    ]
    if let input {
        summary["input"] = input
    }
    return .object(summary)
}

private func routeJSON(_ route: [Compute.Route.Component]) -> JSON {
    .array(route.map { component in
        switch component {
        case .key(let key):
            return .string(key)
        case .index(let index):
            return .int(index)
        }
    })
}

func runtime(
    _ json: JSON,
    in context: Compute.Context = Compute.Context(),
    functions: [any AnyReturnsKeyword] = []
) throws -> Compute.Runtime {
    Compute.Runtime(document: json, context: context, functions: functions)
}

func runtime(
    _ json: JSON,
    in context: Compute.Context = Compute.Context(),
    references: TestReferences
) throws -> Compute.Runtime {
    try runtime(json, in: context, functions: [Compute.Keyword.From.Function(references: references)])
}

func value(
    _ json: JSON,
    in context: Compute.Context = Compute.Context(),
    functions: [any AnyReturnsKeyword] = []
) async throws -> JSON {
    try await runtime(json, in: context, functions: functions).value()
}

func expect(
    _ json: JSON,
    in context: Compute.Context = Compute.Context(),
    equals expected: JSON,
    sourceLocation: SourceLocation = #_sourceLocation
) async throws {
    #expect(try await value(json, in: context) == expected, sourceLocation: sourceLocation)
}

func expect<Value: Decodable & Equatable>(
    _ json: JSON,
    as type: Value.Type = Value.self,
    in context: Compute.Context = Compute.Context(),
    equals expected: Value,
    sourceLocation: SourceLocation = #_sourceLocation
) async throws {
    #expect(try await value(json, in: context).decode(Value.self) == expected, sourceLocation: sourceLocation)
}

func expectNames(
    matching json: JSON,
    _ expected: [String],
    sourceLocation: SourceLocation = #_sourceLocation
) async throws {
    var names: [String] = []
    for user in users where try await value(json, in: Compute.Context(item: user)).decode(Bool.self) {
        names.append(try user.decode(User.self).name)
    }
    #expect(names == expected, sourceLocation: sourceLocation)
}

func expectNext(
    _ iterator: inout AsyncStream<Result<JSON, JSONError>>.Iterator,
    equals expected: Result<JSON, JSONError>,
    sourceLocation: SourceLocation = #_sourceLocation
) async {
    let actual = await iterator.next()
    if actual != expected {
        Issue.record("Expected \(expected), got \(String(describing: actual))", sourceLocation: sourceLocation)
    }
}

func expectJSONError(
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
