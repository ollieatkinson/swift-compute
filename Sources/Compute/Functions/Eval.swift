import JavaScriptCore

extension Keyword {
    public struct Eval: Codable, Equatable, Sendable {
        public static let name = "eval"

        public let expression: JSON
        public let context: [String: JSON]?

        public init(expression: JSON, context: [String: JSON]? = nil) {
            self.expression = expression
            self.context = context
        }
    }
}

extension Keyword.Eval: ComputeKeyword {
    public func compute(in frame: ComputeFrame) async throws -> JSON? {
        let expression = try await expression.compute(frame: frame["expression"])
        var context: [String: JSON] = [:]
        for key in self.context?.keys.sorted() ?? [] {
            guard let value = self.context?[key] else { continue }
            context[key] = try await value.compute(frame: frame["context", .key(key)])
        }

        guard let js = JSContext() else {
            throw JSONError("Could not create JSContext")
        }
        for (key, value) in context {
            js.setObject(value.any, forKeyedSubscript: key as NSString)
        }
        let result = js.evaluateScript(try expression.decode(String.self))
        if let exception = js.exception {
            throw JSONError(exception.toString() ?? "Unknown JavaScript exception")
        }
        return JSON(result?.toObject() ?? NSNull())
    }
}
