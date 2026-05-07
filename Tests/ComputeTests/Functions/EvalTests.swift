import Compute
import Testing

@Suite(.serialized)
struct EvalTests {

    @Test func evaluates_java_script_when_explicitly_registered() async throws {
        #expect(try await value([
            "{returns}": [
                "eval": [
                    "expression": "count + 2",
                    "context": ["count": 40],
                ],
            ],
        ], functions: [Compute.Keywords.Eval.function]) == 42)
    }

    @Test func supports_computed_expression_and_context() async throws {
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
        ], functions: [Compute.Keywords.Eval.function]) == 42)
    }

    @Test func is_not_part_of_the_default_computer() throws {
        #expect(Computer.default["eval"] == nil)
    }
}
