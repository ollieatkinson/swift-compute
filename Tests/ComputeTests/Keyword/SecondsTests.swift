import Compute
import Foundation
import Testing

@Suite(.serialized)
struct SecondsTests {
    @Test func returns_seconds_between_dates() async throws {
        try await expect(
            [
                "{returns}": [
                    "seconds": [
                        "from": [
                            "{returns}": [
                                "date": [
                                    "from": [
                                        "iso": "2024-01-01T00:00:00.000Z",
                                    ],
                                ],
                            ],
                        ],
                        "to": [
                            "{returns}": [
                                "date": [
                                    "since": [
                                        "epoch": 1_704_067_290.5,
                                    ],
                                ],
                            ],
                        ],
                    ],
                ],
            ],
            equals: 90.5
        )
    }

    @Test func computes_seconds_inputs() async throws {
        try await expect(
            [
                "{returns}": [
                    "seconds": [
                        "from": ["{returns}": ["item": ["started_at"]]],
                        "to": ["{returns}": ["item": ["finished_at"]]],
                    ],
                ],
            ],
            in: Compute.Context(item: [
                "started_at": JSON(Foundation.Date(timeIntervalSince1970: 1_704_067_200)),
                "finished_at": JSON(Foundation.Date(timeIntervalSince1970: 1_704_067_245)),
            ]),
            equals: 45.0
        )
    }
}
