import CustomDump
import Foundation

extension Brain {
    public nonisolated func _printChanges(
        _ label: String = "🧠",
        printer: @escaping @Sendable (String) async -> Void = { print($0) }
    ) -> AsyncStream<State> {
        AsyncStream { continuation in
            let task = Task {
                var previous: State?
                for await state in states() {
                    let thoughts = await self.thoughts
                    await printer(ChangeLog.render(
                        label: label,
                        thoughts: thoughts,
                        previous: previous,
                        current: state
                    ))
                    previous = state
                    continuation.yield(state)
                }
                continuation.finish()
            }
            continuation.onTermination = { @Sendable _ in
                task.cancel()
            }
        }
    }
}

extension ComputeRuntime {
    public nonisolated func _printChanges(
        at route: ComputeRoute = .root,
        _ label: String = "⏳",
        printer: @escaping @Sendable (String) async -> Void = { print($0) }
    ) -> AsyncStream<Result<JSON, JSONError>> {
        AsyncStream { continuation in
            let task = Task {
                var previous: JSON?
                for await result in run(at: route) {
                    let thoughts = await self.thoughts
                    await printer(ChangeLog.render(
                        label: label,
                        route: route,
                        result: result,
                        thoughts: thoughts,
                        previous: previous
                    ))
                    if case .success(let value) = result {
                        previous = value
                    }
                    continuation.yield(result)
                }
                continuation.finish()
            }
            continuation.onTermination = { @Sendable _ in
                task.cancel()
            }
        }
    }
}

private enum ChangeLog {
    static func render<State: Equatable, Thoughts: Collection>(
        label: String,
        thoughts: Thoughts,
        previous: State?,
        current: State
    ) -> String {
        var lines = ["\(label)._printChanges"]
        append(thoughts, to: &lines)
        appendState(previous: previous, current: current, to: &lines)
        return lines.joined(separator: "\n")
    }

    static func render(
        label: String,
        route: ComputeRoute,
        result: Result<JSON, JSONError>,
        thoughts: [ComputeThought],
        previous: JSON?
    ) -> String {
        var lines = ["\(label)._printChanges"]
        lines.append("  route: \(route.path.isEmpty ? "/" : route.path.joined(separator: "."))")
        switch result {
        case .success(let current):
            lines.append("  event: ✅ success")
            append(thoughts, to: &lines)
            appendState(previous: previous, current: current, to: &lines)
        case .failure(let error):
            lines.append("  event: ❌ failure")
            lines.append("  error:")
            lines.append(dumped(error, indentation: 4))
        }
        return lines.joined(separator: "\n")
    }

    private static func append<Thoughts: Collection>(_ thoughts: Thoughts, to lines: inout [String]) {
        guard !thoughts.isEmpty else { return }
        lines.append("  thoughts:")
        lines.append(dumped(thoughts, indentation: 4))
    }

    private static func append(_ thoughts: [ComputeThought], to lines: inout [String]) {
        guard !thoughts.isEmpty else { return }
        lines.append("  thoughts:")
        for (index, thought) in thoughts.enumerated() {
            lines.append("    [\(index)] \(thought.kind.rawValue) \(thought.keyword) @ \(path(thought.route)) -> \(output(thought))")
        }
    }

    private static func appendState<State: Equatable>(
        previous: State?,
        current: State,
        to lines: inout [String]
    ) {
        guard let previous else {
            lines.append("  state:")
            lines.append(dumped(current, indentation: 4))
            return
        }
        lines.append("  state diff:")
        if let difference = diff(previous, current) {
            lines.append(indent(difference, by: 4))
        } else {
            lines.append("    No changes.")
        }
    }

    private static func dumped<Value>(_ value: Value, indentation: Int) -> String {
        var output = ""
        customDump(value, to: &output)
        return indent(output, by: indentation)
    }

    private static func indent(_ output: String, by spaces: Int) -> String {
        let prefix = String(repeating: " ", count: spaces)
        return output
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { prefix + $0 }
            .joined(separator: "\n")
    }

    private static func path(_ route: ComputeRoute) -> String {
        route.path.isEmpty ? "/" : route.path.joined(separator: ".")
    }

    private static func output(_ thought: ComputeThought) -> String {
        if let error = thought.error {
            return "throw \(error.description)"
        }
        guard let output = thought.output else {
            return "nil"
        }
        return compact(output)
    }

    private static func compact(_ json: JSON) -> String {
        switch json {
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
            return json.stableDescription
        }
    }
}
