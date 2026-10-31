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
    @Test(arguments: [
        ("GBP", "en_GB", "£72.50"), ("USD", "en_US", "$72.50"), ("EUR", "de_DE", "72,50 €"),
        ("JPY", "ja_JP", "¥72"),
    ])
    func formats_computed_currency_values_with_the_authored_locale(currency: String, locale: String, expected: String) async throws {
        try await expect(.returns("text", ["from": ["number": [
            "value": JSON.returns("item", ["amount"]), "currency": JSON.returns("item", ["currency"]),
            "locale": JSON.returns("item", ["locale"]),
        ]]]), in: Compute.Context(item: ["amount": 72.5, "currency": .string(currency), "locale": .string(locale)]), equals: .string(expected))
    }

    @Test func formats_plain_numbers_and_rejects_invalid_numeric_inputs() async throws {
        try await expect(.returns("text", ["from": ["number": ["value": 1234.5, "locale": "de_DE"]]]), equals: "1.234,5")
        try await expect(.returns("text", ["from": ["number": ["value": 1234.5]]]), equals: "1234.5")
        await expectJSONError(containing: "finite number") {
            _ = try await value(.returns("text", ["from": ["number": ["value": .double(.infinity)]]]))
        }
        await expectJSONError(containing: "currency code") {
            _ = try await value(.returns("text", ["from": ["number": ["value": 72.5, "currency": ""]]]))
        }
        await #expect(throws: JSONError.self) {
            try await value(.returns("text", ["from": ["number": ["value": .null]]]))
        }
    }

}
