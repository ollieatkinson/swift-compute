import Compute
import Testing

@Suite
struct ComputerTests {

    @Test func classifiesKeywordsFromReturnsJSON() throws {
        let references = TestReferences()
        let computer = Computer.default.merging([
            From.Function(references: references),
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

    private func keyword(in json: JSON, using computer: Computer) throws -> Compute.Keyword? {
        guard case .object(let object) = json else {
            throw JSONError("Expected object")
        }
        return Compute.Keyword(returns: object, computer: computer)
    }
}
