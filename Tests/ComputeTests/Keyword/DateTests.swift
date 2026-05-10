import Compute
import Foundation
import Testing

@Suite(.serialized)
struct DateTests {
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

    @Test func creates_dates_from_iso_strings() async throws {
        let result = try await value([
            "{returns}": [
                "date": [
                    "from": [
                        "iso": "2024-01-01T00:00:00.250Z",
                    ],
                ],
            ],
        ])

        #expect(result.rawValue as? Foundation.Date == Foundation.Date(timeIntervalSince1970: 1_704_067_200.25))
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
    }

    @Test func invalid_date_payloads_throw() async throws {
        await expectJSONError(containing: "Not a valid date") {
            _ = try await value([
                "{returns}": [
                    "date": [
                        "from": [
                            "iso": "2024-01-01T00:00:00Z",
                        ],
                    ],
                ],
            ])
        }
    }
}
