import Testing

@Suite(.serialized)
struct LessOrEqualTests {

    @Test func evaluates_inclusive_ordering() async throws {
        try await expect(["{returns}": ["comparison": ["less_or_equal": ["lhs": 1, "rhs": 1]]]], equals: true)
        try await expect(["{returns}": ["comparison": ["less_or_equal": ["lhs": 2, "rhs": 1]]]], equals: false)
    }
}
