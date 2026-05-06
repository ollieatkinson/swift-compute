import Compute
import Testing

@Suite(.serialized)
struct EvalTests {

    @Test func evaluatesJavaScriptWhenExplicitlyRegistered() async throws {
        #expect(try await value([
            "{returns}": [
                "eval": [
                    "expression": "count + 2",
                    "context": ["count": 40],
                ],
            ],
        ], functions: [Keyword.Eval.function]) == 42)
    }

    @Test func supportsComputedExpressionAndContext() async throws {
        #expect(try await value([
            "{returns}": [
                "eval": [
                    "expression": ["{returns}": ["this": ["value": "first + second"]]],
                    "context": [
                        "first": ["{returns}": ["this": ["value": 20]]],
                        "second": 22,
                    ],
                ],
            ],
        ], functions: [Keyword.Eval.function]) == 42)
    }

    @Test func isNotPartOfTheDefaultComputer() throws {
        #expect(Computer.default["eval"] == nil)
    }
}
