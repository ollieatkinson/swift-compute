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

    private static func append<Thoughts: Collection>(_ thoughts: Thoughts, to lines: inout [String]) {
        guard !thoughts.isEmpty else { return }
        lines.append("  thoughts:")
        lines.append(dumped(thoughts, indentation: 4))
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
}
