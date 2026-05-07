import Foundation

#if canImport(FoundationModels) && (os(iOS) || os(macOS))
import FoundationModels
#endif

extension Keyword {
    public struct Explain: Codable, Equatable, Sendable {
        public enum Mode: String, Codable, Equatable, Sendable {
            case trace
            case foundationModel = "foundation_model"
        }

        public static let name = "explain"

        public let value: JSON
        public let mode: Mode
        public let context: JSON?

        public init(value: JSON, mode: Mode = .trace, context: JSON? = nil) {
            self.value = value
            self.mode = mode
            self.context = context
        }

        private enum CodingKeys: String, CodingKey {
            case value
            case mode
            case context
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            self.value = try container.decode(JSON.self, forKey: .value)
            self.mode = try container.decodeIfPresent(Mode.self, forKey: .mode) ?? .trace
            self.context = try container.decodeIfPresent(JSON.self, forKey: .context)
        }
    }
}

extension Keyword.Explain: ComputeKeyword {
    public func compute() throws -> JSON {
        value
    }
}

extension Keyword.Explain: CustomComputeKeyword {
    func compute(
        context: Compute.Context,
        runtime: ComputeFunctionRuntime,
        route: ComputeRoute,
        depth: Int
    ) async throws -> JSON? {
        let capture = await runtime.capture {
            try await value.compute(
                context: context,
                runtime: runtime,
                route: route.appending(.key("value")),
                depth: depth
            )
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
                localItem: context.item
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

private extension Keyword.Explain {
    func naturalLanguageExplanation(computedValue: JSON, thoughts: [ComputeThought], localItem: JSON?) async -> String? {
        guard mode == .foundationModel else { return nil }
#if canImport(FoundationModels) && (os(iOS) || os(macOS))
        if #available(iOS 26.0, macOS 26.0, *) {
            return await FoundationModelExplainProvider.explanation(
                expression: value,
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
private enum FoundationModelExplainProvider {
    static func explanation(
        expression: JSON,
        computedValue: JSON,
        thoughts: [ComputeThought],
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
            let explanation = response.content
                .replacingOccurrences(of: "**", with: "")
                .replacingOccurrences(of: "*", with: "")
                .replacingOccurrences(of: "`", with: "")
                .replacingOccurrences(of: "#", with: "")
                .components(separatedBy: .whitespacesAndNewlines)
                .filter { !$0.isEmpty }
                .joined(separator: " ")
            return explanation.isEmpty ? nil : explanation
        } catch {
            return nil
        }
    }

    private static let instructions = """
    Write exactly one clear plain-English sentence for an end user, suitable for a tooltip. The context is important because it describes where or how the result is consumed. Use fields such as "label", "surface", and "purpose" to understand what the user is seeing, but do not copy them as a heading or prefix. The result and trace are authoritative. Use the trace and referenced local data to explain why. Start with the user-facing outcome, such as "You can..." when the context supports it, not "This result..." or "The result...". For boolean results, explain the actual outcome in context instead of writing true or false. Preserve exact identifiers, comparison relationships, and values. Include the key exact values that explain the outcome, especially numbers and codes used in comparisons or membership checks. For comparisons, keep the observed value and threshold separate; for example, say "74% is greater than or equal to 20%" rather than "74% or higher". Do not expand or reinterpret codes or values; for example, keep "GB" as "GB" instead of changing it to "UK" or "United Kingdom". Translate internal names such as "greater_or_equal" into natural language such as "greater than or equal to". Do not start with a title, heading, label, "result", or "explanation". Do not mention tooltip, JSON, Compute, use markdown, add a heading, make a list, show step-by-step reasoning, quote the example text, invent context, or include raw internal keyword names.
    """

    private static func prompt(
        expression: JSON,
        computedValue: JSON,
        thoughts: [ComputeThought],
        explanationContext: JSON?,
        localItem: JSON?
    ) -> String {
        """
        Important user-facing context:
        \(explanationContext?.promptDescription ?? "Not provided.")

        Referenced local data:
        \(referencedLocalData(localItem: localItem, thoughts: thoughts)?.promptDescription ?? "Not provided.")

        Expression:
        \(expression.promptDescription)

        Result:
        \(computedValue.promptDescription)

        Evaluation trace:
        \(JSON.array(thoughts.map(\.modelExplanationJSON)).promptDescription)

        Explain what the result means in the user-facing context, and why it happened, in exactly one sentence.
        """
    }

    private static func referencedLocalData(localItem: JSON?, thoughts: [ComputeThought]) -> JSON? {
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

private extension ComputeThought {
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
