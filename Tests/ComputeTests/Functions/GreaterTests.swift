import Testing

@Suite(.serialized)
struct GreaterTests {

    @Test func evaluates_strict_ordering() async throws {
        try await expect(["{returns}": ["comparison": ["greater": ["lhs": 1, "rhs": 2]]]], equals: false)
        try await expect(["{returns}": ["comparison": ["greater": ["lhs": 1, "rhs": 1]]]], equals: false)
        try await expect(["{returns}": ["comparison": ["greater": ["lhs": 1, "rhs": 0]]]], equals: true)
    }
}
