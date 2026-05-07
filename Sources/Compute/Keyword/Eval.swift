import JavaScriptCore

extension Compute.Keyword {
    public struct Eval: Codable, Equatable, Sendable {
        public static let name = "eval"

        @Computed public var expression: JSON
        @Computed public var context: [String: JSON]?
    }
}

extension Compute.Keyword.Eval: Compute.KeywordDefinition {
    public func compute(in frame: Compute.Frame) async throws -> JSON? {
        let expression = try await $expression.compute(in: frame)
        let context = try await $context.compute(in: frame) ?? [:]

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
