import Compute
import Testing

@Suite
struct ComputerTests {

    @Test func classifies_keywords_from_returns_json() throws {
        let references = TestReferences()
        let computer = Computer.default.merging([
            Compute.Keyword.From.Function(references: references),
            Echo.function,
        ])

        let count = try keyword(in: ["{returns}": ["count": ["of": [1, 2, 3]]]], using: computer)
        #expect(count?.name == "count")
        #expect(count?.isComputeKeyword == true)
        #expect(count?.isReturnsKeyword == false)

        let from = try keyword(in: ["{returns}": ["from": ["reference": "people"]]], using: computer)
        #expect(from?.name == "from")
        #expect(from?.isComputeKeyword == false)
        #expect(from?.isReturnsKeyword == true)

        let echo = try keyword(in: ["{returns}": ["echo": "value"]], using: computer)
        #expect(echo?.name == "echo")
        #expect(echo?.isComputeKeyword == true)
        #expect(echo?.isReturnsKeyword == false)

        #expect(try keyword(in: ["{returns}": ["missing": nil]], using: computer) == nil)
    }

    private func keyword(in json: JSON, using computer: Computer) throws -> Computer.RegisteredKeyword? {
        guard let object = json.object else {
            throw JSONError("Expected object")
        }
        return Computer.RegisteredKeyword(returns: object, computer: computer)
    }
}
