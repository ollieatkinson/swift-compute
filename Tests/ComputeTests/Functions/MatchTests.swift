import Testing

@Suite(.serialized)
struct MatchTests {

    @Test func evaluates_regular_expression_matches() async throws {
        try await expect(["{returns}": ["comparison": ["match": ["lhs": "Hello World", "rhs": "Hel{2}o\\sWorld"]]]], equals: true)
        try await expect(["{returns}": ["comparison": ["match": ["lhs": "Bye World", "rhs": "Hel{2}o\\sWorld"]]]], equals: false)
    }
}
