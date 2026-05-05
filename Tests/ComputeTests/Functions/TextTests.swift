import Compute
import Testing

@Suite(.serialized)
struct TextTests {

    @Test func joinsResolvedStringsWithSeparatorAndTerminator() async throws {
        let json: JSON = [
            "{returns}": [
                "text": [
                    "from": [
                        "joining": [
                            "array": [
                                ["{returns}": ["item": ["first"]]],
                                ["{returns}": ["item": ["second"]]],
                                "done",
                            ],
                            "separator": " / ",
                            "terminator": ".",
                        ],
                    ],
                ],
            ],
        ]

        try await expect(
            json,
            in: Compute.Context(item: ["first": "ready", "second": "steady"]),
            equals: "ready / steady / done."
        )
    }

    @Test func defaultsToEmptySeparatorAndTerminator() async throws {
        try await expect(
            [
                "{returns}": [
                    "text": [
                        "from": [
                            "joining": [
                                "array": ["A", "B", "C"],
                            ],
                        ],
                    ],
                ],
            ],
            equals: "ABC"
        )
    }
}
