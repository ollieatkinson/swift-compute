import Testing

@Suite(.serialized)
struct LessTests {

    @Test func evaluatesStrictOrdering() async throws {
        try await expect(["{returns}": ["comparison": ["less": ["lhs": 1, "rhs": 2]]]], equals: true)
        try await expect(["{returns}": ["comparison": ["less": ["lhs": 1, "rhs": 1]]]], equals: false)
        try await expect(["{returns}": ["comparison": ["less": ["lhs": 1, "rhs": 0]]]], equals: false)
    }
}
