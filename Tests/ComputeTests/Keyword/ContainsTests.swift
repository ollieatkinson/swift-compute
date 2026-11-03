import Compute
import Testing

@Suite(.serialized)
struct ContainsTests {

    @Test func evaluates_string_containment() async throws {
        let json: JSON = [
            "{returns}": [
                "contains": [
                    "lhs": ["{returns}": ["item": ["name"]]],
                    "rhs": "os",
                ],
            ],
        ]

        try await expect(json, in: Compute.Context(item: users[0]), equals: true)
        try await expect(json, in: Compute.Context(item: users[1]), equals: false)
    }

    @Test func evaluates_array_containment() async throws {
        try await expect(
            [
                "{returns}": [
                    "contains": [
                        "lhs": [36, 37, 38],
                        "rhs": ["{returns}": ["item": ["age"]]],
                    ],
                ],
            ],
            in: Compute.Context(item: users[1]),
            equals: true
        )
    }
    @Test(arguments: [
        ("Sky Atlantic", "sky", false, true),
        ("Sky Atlantic", "sky", true, false),
        ("CAFÉ", "café", false, true),
        ("Café", "cafe", false, false),
        ("Sky [HD]", "[hd]", false, true),
        ("Sky Atlantic", ".*", false, false),
        ("", "", false, true),
        ("Sky", "", false, true),
    ])
    func string_matching_can_ignore_case_without_treating_input_as_a_pattern(
        lhs: String, rhs: String, sensitive: Bool, expected: Bool
    ) async throws {
        try await expect(.returns("contains", [
            "lhs": .string(lhs), "rhs": .string(rhs), "case_sensitive": .bool(sensitive),
        ]), equals: .bool(expected))
    }

    @Test func default_array_equality_is_unchanged_and_text_options_reject_wrong_types() async throws {
        try await expect(.returns("contains", ["lhs": "Sky", "rhs": "sky"]), equals: false)
        try await expect(.returns("contains", ["lhs": ["Sky", ["id": 1]], "rhs": "sky"]), equals: false)
        try await expect(.returns("contains", ["lhs": ["Sky", ["id": 1]], "rhs": ["id": 1]]), equals: true)
        for option: JSON in ["false", 0, [:]] {
            await #expect(throws: JSONError.self) {
                try await value(.returns("contains", ["lhs": "Sky", "rhs": "sky", "case_sensitive": option]))
            }
        }
        await expectJSONError(containing: "only to strings") {
            _ = try await value(.returns("contains", ["lhs": ["Sky"], "rhs": "sky", "case_sensitive": false]))
        }
    }

    @Test func text_and_case_mode_remain_live_compute_dependencies() async throws {
        let references = TestReferences()
        await references.set("query", to: "sky")
        await references.set("sensitive", to: false)
        let runtime = try runtime(.returns("contains", [
            "lhs": "Sky Atlantic", "rhs": .returns("from", ["reference": "query"]),
            "case_sensitive": .returns("from", ["reference": "sensitive"]),
        ]), references: references)
        defer { await runtime.cancel(); await references.finish() }
        var values = runtime.run().makeAsyncIterator()
        #expect(await values.next() == .success(true))
        await references.set("sensitive", to: true)
        #expect(await values.next() == .success(false))
        await references.set("query", to: "Sky")
        #expect(await values.next() == .success(true))
    }

}
