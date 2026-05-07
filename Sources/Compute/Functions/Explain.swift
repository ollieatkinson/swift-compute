extension Keyword {
    public struct Explain: Codable, Equatable, Sendable {
        public static let name = "explain"

        public let value: JSON

        public init(value: JSON) {
            self.value = value
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
            return [
                "ok": true,
                "summary": .string(value.explanationSummary),
                "thoughts": thoughts,
                "value": value,
            ]
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
}

private extension JSON {
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
