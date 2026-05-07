import Compute
import Testing

@Suite(.serialized)
struct TextTests {

    @Test func joins_resolved_strings_with_separator_and_terminator() async throws {
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

    @Test func defaults_to_empty_separator_and_terminator() async throws {
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
