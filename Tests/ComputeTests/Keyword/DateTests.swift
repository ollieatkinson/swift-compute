import Compute
import Foundation
import Testing

@Suite(.serialized)
struct DateTests {
    @Test(arguments: ["2024-01-01T00:00:00.1234567890Z", "2024-01-01T01:30:00.123456789012+01:30"])
    func long_fractional_timestamps_keep_the_compatible_formatter_fallback(source: String) async throws {
        let result = try await value(.returns("date", ["from": ["iso": .string(source)]]))
        let date = try #require(result.rawValue as? Foundation.Date)
        let previous = ISO8601DateFormatter()
        previous.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        #expect(date == previous.date(from: source))
    }

    @Test func native_dates_remain_composable_through_json_templates_and_explanations() async throws {
        let date = JSON.returns("date", ["since": ["epoch": 0]])
        let mapped = JSON.returns("map", ["src": JSON.returns("this", ["value": date])])
        #expect(try await value(mapped).rawValue as? Foundation.Date == Foundation.Date(timeIntervalSince1970: 0))
        let explanation = try await value(.returns("explain", ["value": mapped]))
        #expect(explanation.object?["value"]?.rawValue as? Foundation.Date == Foundation.Date(timeIntervalSince1970: 0))
    }

    @Test func creates_dates_from_epoch_seconds() async throws {
        let result = try await value([
            "{returns}": [
                "date": [
                    "since": [
                        "epoch": 1_704_067_200.25,
                    ],
                ],
            ],
        ])

        #expect(result.rawValue as? Foundation.Date == Foundation.Date(timeIntervalSince1970: 1_704_067_200.25))
    }

    @Test(arguments: [
        ("2024-01-01T00:00:00Z", 0.0),
        ("2024-01-01T00:00:00.250Z", 0.25),
        ("2024-01-01T01:30:00+01:30", 0.0),
        ("2024-01-01T01:30:00.250+01:30", 0.25),
        ("2023-12-31T19:00:00.125-05:00", 0.125),
    ])
    func creates_dates_from_iso_strings(source: String, fraction: Double) async throws {
        let result = try await value(.returns("date", ["from": ["iso": .string(source)]]))
        #expect(result.rawValue as? Foundation.Date == Foundation.Date(timeIntervalSince1970: 1_704_067_200 + fraction))
    }

    @Test func computes_date_inputs() async throws {
        let result = try await value(
            [
                "{returns}": [
                    "date": [
                        "since": [
                            "epoch": ["{returns}": ["item": ["epoch"]]],
                        ],
                    ],
                ],
            ],
            in: Compute.Context(item: ["epoch": 1_704_067_200])
        )

        #expect(result.rawValue as? Foundation.Date == Foundation.Date(timeIntervalSince1970: 1_704_067_200))

        let shifted = try await value(.returns("date", [
            "from": ["iso": .returns("item", ["iso"])], "offset": .returns("item", ["offset"]),
        ]), in: Compute.Context(item: ["iso": "2024-01-01T01:30:00.250+01:30", "offset": 60]))
        #expect(shifted.rawValue as? Foundation.Date == Foundation.Date(timeIntervalSince1970: 1_704_067_260.25))
    }

    @Test(arguments: ["not-a-date", "2024-01-01T00:00:00.xyzZ", "2024-01-01T00:00:00"])
    func invalid_date_payloads_throw(source: String) async throws {
        await expectJSONError(containing: "Not a valid date") {
            _ = try await value([
                "{returns}": [
                    "date": [
                        "from": [
                            "iso": .string(source),
                        ],
                    ],
                ],
            ])
        }
    }
}
