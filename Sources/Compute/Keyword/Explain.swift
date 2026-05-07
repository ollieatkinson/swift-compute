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
        public let mode: Mode
        public let context: JSON?

        private enum CodingKeys: String, CodingKey {
            case value
            case mode
            case context
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            self._value = try container.decode(Computed<JSON>.self, forKey: .value)
            self.mode = try container.decodeIfPresent(Mode.self, forKey: .mode) ?? .trace
            self.context = try container.decodeIfPresent(JSON.self, forKey: .context)
        }
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
                thoughts: capture.thoughts,
                localItem: frame.context.item
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
    func naturalLanguageExplanation(computedValue: JSON, thoughts: [Compute.Thought], localItem: JSON?) async -> String? {
        guard mode == .foundationModel else { return nil }
#if canImport(FoundationModels) && (os(iOS) || os(macOS))
        if #available(iOS 26.0, macOS 26.0, *) {
            return await FoundationModelPrompt.explanation(
                expression: $value.rawValue,
                computedValue: computedValue,
                thoughts: thoughts,
                explanationContext: context,
                localItem: localItem
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
        explanationContext: JSON?,
        localItem: JSON?
    ) async -> String? {
        let model = SystemLanguageModel.default
        guard model.isAvailable else { return nil }

        do {
            let session = LanguageModelSession(instructions: instructions)
            let response = try await session.respond(to: prompt(
                expression: expression,
                computedValue: computedValue,
                thoughts: thoughts,
                explanationContext: explanationContext,
                localItem: localItem
            ))
            let explanation = response.content.trimmingCharacters(in: .whitespacesAndNewlines)
            return explanation.isEmpty ? nil : explanation
        } catch {
            return nil
        }
    }

    private static let instructions = """
    Write one user-facing explanation sentence in plain text only.
    Use second person, starting with "You are seeing this because" when context describes a visible state.
    Use the context, result, referenced data, and trace.
    Explain the outcome and key reason, keeping exact values, identifiers, and comparisons.
    For booleans, explain the outcome instead of saying true or false.
    Do not use Markdown, headings, lists, labels, raw keyword names, invented context, or "The user".
    """

    private static func prompt(
        expression: JSON,
        computedValue: JSON,
        thoughts: [Compute.Thought],
        explanationContext: JSON?,
        localItem: JSON?
    ) -> String {
        """
        Context:
        \(explanationContext?.promptDescription ?? "Not provided.")

        Referenced data:
        \(referencedLocalData(localItem: localItem, thoughts: thoughts)?.promptDescription ?? "Not provided.")

        Expression:
        \(expression.promptDescription)

        Result:
        \(computedValue.promptDescription)

        Trace:
        \(JSON.array(thoughts.map(\.modelExplanationJSON)).promptDescription)

        Reply with one plain-text sentence explaining why you are seeing this result.
        """
    }

    private static func referencedLocalData(localItem: JSON?, thoughts: [Compute.Thought]) -> JSON? {
        guard localItem != nil else { return nil }

        let values = thoughts.compactMap { thought -> JSON? in
            guard case .object(let input)? = thought.input else { return nil }
            guard case .array(let path)? = input["item"] else { return nil }
            let value = thought.output ?? .null
            return [
                "path": .array(path),
                "value": value,
            ]
        }

        return values.isEmpty ? nil : .array(values)
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
            return explanationSummary
        }
        return String(decoding: data, as: UTF8.self)
    }

    var explanationSummary: String {
        switch self {
        case .null:
            return "null"
        case .bool(let value):
            return String(value)
        case .int(let value):
            return String(value)
        case .double(let value):
            return String(value)
        case .string(let value):
            return value
        case .array, .object:
            return stableDescription
        }
    }
}
