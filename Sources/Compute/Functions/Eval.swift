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
    public func compute() throws -> JSON {
        guard let js = JSContext() else {
            throw JSONError("Could not create JSContext")
        }
        for (key, value) in context ?? [:] {
            js.setObject(value.any, forKeyedSubscript: key as NSString)
        }
        let result = js.evaluateScript(try expression.decode(String.self))
        if let exception = js.exception {
            throw JSONError(exception.toString() ?? "Unknown JavaScript exception")
        }
        return JSON(result?.toObject() ?? NSNull())
    }
}
