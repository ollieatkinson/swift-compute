import _JSON
import Foundation

#if canImport(FoundationModels) && (os(iOS) || os(macOS))
import FoundationModels
#endif

extension Compute.Keyword {
    public struct Explain: Codable, Equatable, Sendable {
        public enum Mode: String, Codable, Equatable, Sendable {
            case trace
            case foundationModel = "foundation_model"
        }

        public static let name = "explain"

        @Computed public var value: JSON
        public let mode: Mode?
        public let context: JSON?
    }
}

extension Compute.Keyword.Explain: Compute.KeywordDefinition {

    public func compute(in frame: Compute.Frame) async throws -> JSON? {
        let capture = await frame.runtime.capture {
            try await $value.compute(in: frame)
        }

        let thoughts = JSON.array(capture.thoughts.map(\.explanationJSON))
        switch capture.result {
        case .success(let value):
            var payload: [String: JSON] = [
                "ok": true,
                "summary": .string(value.explanationSummary),
                "thoughts": thoughts,
                "value": value,
            ]
            if let explanation = await naturalLanguageExplanation(
                computedValue: value,
                thoughts: capture.thoughts
            ) {
                payload["explanation"] = .string(explanation)
            }
            return .object(payload)
        case .failure(let error):
            return [
                "error": .string(error.description),
                "ok": false,
                "thoughts": thoughts,
                "value": .null,
            ]
        }
    }
}

private extension Compute.Keyword.Explain {
    func naturalLanguageExplanation(computedValue: JSON, thoughts: [Compute.Thought]) async -> String? {
        guard mode == .foundationModel else { return nil }
#if canImport(FoundationModels) && (os(iOS) || os(macOS))
        if #available(iOS 26.0, macOS 26.0, *) {
            return await FoundationModelPrompt.explanation(
                expression: $value.rawValue,
                computedValue: computedValue,
                thoughts: thoughts,
                explanationContext: context
            )
        }
#endif
        return nil
    }
}

#if canImport(FoundationModels) && (os(iOS) || os(macOS))
@available(iOS 26.0, macOS 26.0, *)
private enum FoundationModelPrompt {
    static func explanation(
        expression: JSON,
        computedValue: JSON,
        thoughts: [Compute.Thought],
        explanationContext: JSON?
    ) async -> String? {
        let model = SystemLanguageModel.default
        guard model.isAvailable else { return nil }

        do {
            let session = LanguageModelSession(instructions: instructions)
            let response = try await session.respond(to: prompt(
                expression: expression,
                computedValue: computedValue,
                thoughts: thoughts,
                explanationContext: explanationContext
            ))
            let explanation = response.content.trimmingCharacters(in: .whitespacesAndNewlines)
            return explanation.isEmpty ? nil : explanation
        } catch {
            return nil
        }
    }

    private static let instructions = """
    Convert runtime evidence into one user-facing sentence.
    Begin exactly with "You are seeing this because".
    Use "you" and "your"; never say "the user".
    Use the exact final value and exact trace outputs.
    For false final values, do not mention passed checks unless needed for contrast.
    For true final values, do not mention failed branches unless they selected a fallback.
    For `unless`, true means blocked and false means not blocked.
    For `not`, true means the original source was false.
    For `either`, explain the branch that produced the final value.
    For lists, name the returned people or items.
    Do not expose any raw compute or JSON vocabulary.
    """

    private static func prompt(
        expression: JSON,
        computedValue: JSON,
        thoughts: [Compute.Thought],
        explanationContext: JSON?
    ) -> String {
        """
        Context:
        \(explanationContext?.promptDescription ?? "Not provided.")

        Expression:
        \(expression.promptDescription)

        Final value:
        \(computedValue.promptDescription)

        Runtime evidence:
        \(JSON.array(thoughts.map(\.modelExplanationJSON)).promptDescription)

        One sentence:
        """
    }
}
#endif

private extension Compute.Thought {
    var explanationJSON: JSON {
        var object: [String: JSON] = [
            "depth": .int(depth),
            "keyword": .string(keyword),
            "kind": .string(kind.rawValue),
            "route": .array(route.path.map(JSON.string)),
        ]
        if let output {
            object["output"] = .string(output.explanationSummary)
        }
        if let error {
            object["error"] = .string(error.description)
        }
        return .object(object)
    }

    var modelExplanationJSON: JSON {
        var object: [String: JSON] = [
            "depth": .int(depth),
            "keyword": .string(keyword),
            "kind": .string(kind.rawValue),
            "route": .array(route.path.map(JSON.string)),
        ]
        if let input {
            object["input"] = input
        }
        if let output {
            object["output"] = output
        }
        return .object(object)
    }
}

private extension JSON {
    var promptDescription: String {
        guard let data = try? JSONSerialization.data(withJSONObject: any, options: [.fragmentsAllowed, .sortedKeys]) else {
            return String(describing: rawValue)
        }
        return String(decoding: data, as: UTF8.self)
    }

    var explanationSummary: String {
        if isNull {
            return "null"
        }
        if let value = bool {
            return String(value)
        }
        if let value = int {
            return String(value)
        }
        if let value = double {
            return String(value)
        }
        if let value = string {
            return value
        }
        return promptDescription
    }
}
