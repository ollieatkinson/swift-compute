import Compute
import Foundation
import Testing

@Suite(.serialized)
struct ArraySortTests {

    @Test func sorts_values_and_objects_with_stable_fallbacks() async throws {
        try await expect(["{returns}": ["array_sort": ["array": [3, 1, 2], "predicates": [["order": "ascending"]]]]], equals: [1, 2, 3])
        try await expect(["{returns}": ["array_sort": ["array": ["b", "c", "a"], "predicates": [["order": "descending"]]]]], equals: ["c", "b", "a"])
        try await expect([
            "{returns}": [
                "array_sort": [
                    "array": [
                        ["name": "b", "rank": 2],
                        ["name": "a", "rank": 1],
                        ["name": "c", "rank": 2],
                    ],
                    "predicates": [
                        ["key_path": ["rank"], "order": "ascending"],
                        ["key_path": ["name"], "order": "descending"],
                    ],
                ],
            ],
        ], equals: [
            ["name": "a", "rank": 1],
            ["name": "c", "rank": 2],
            ["name": "b", "rank": 2],
        ])
    }

    @Test(arguments: [Compute.Keyword.ArraySort.Order.ascending, .descending])
    func sorts_native_dates_by_instant_and_keeps_equal_dates_stable(
        order: Compute.Keyword.ArraySort.Order
    ) async throws {
        func date(_ iso: String) -> JSON {
            ["{returns}": ["date": ["from": ["iso": .string(iso)]]]]
        }
        let late = date("1970-01-01T02:00:00Z")
        let early = date("1970-01-01T02:00:00+01:00")
        let same = date("1970-01-01T01:00:00Z")
        let result = try await value(["{returns}": ["array_sort": [
            "array": [["name": "late", "time": late],
                      ["name": "early", "time": early],
                      ["name": "same", "time": same]],
            "predicates": [["key_path": ["time"], "order": .string(order.rawValue)]]
        ]]])
        #expect(result.array?.compactMap { $0.object?["name"]?.string } ==
            (order == .ascending ? ["early", "same", "late"] : ["late", "early", "same"]))
        let first = JSON(Date(timeIntervalSince1970: 3600))
        let last = JSON(Date(timeIntervalSince1970: 7200))
        try await expect(["{returns}": ["array_sort": [
            "array": [late, early],
            "predicates": [["order": .string(order.rawValue)]]
        ]]], equals: .array(order == .ascending ? [first, last] : [last, first]))
    }

    @Test func returns_identity_without_predicates() async throws {
        try await expect(["{returns}": ["array_sort": ["array": [3, 1, 2]]]], equals: [3, 1, 2])
    }

    @Test func resolves_computed_array_inputs() async throws {
        try await expect(
            [
                "{returns}": [
                    "array_sort": [
                        "array": ["{returns}": ["item": ["scores"]]],
                        "predicates": [["order": "ascending"]],
                    ],
                ],
            ],
            in: Compute.Context(item: ["scores": [3, 1, 2]]),
            equals: [1, 2, 3]
        )
    }

    @Test func computes_predicate_plan_before_sorting() async throws {
        try await expect(
            [
                "{returns}": [
                    "array_sort": [
                        "array": [
                            ["name": "first", "rank": 1],
                            ["name": "third", "rank": 3],
                            ["name": "second", "rank": 2],
                        ],
                        "predicates": [
                            "{returns}": [
                                "this": [
                                    "value": [
                                        [
                                            "key_path": [
                                                ["{returns}": ["item": ["sortKey"]]],
                                            ],
                                            "order": ["{returns}": ["item": ["sortOrder"]]],
                                        ],
                                    ],
                                ],
                            ],
                        ],
                    ],
                ],
            ],
            in: Compute.Context(item: [
                "sortKey": "rank",
                "sortOrder": "descending",
            ]),
            equals: [
                ["name": "third", "rank": 3],
                ["name": "second", "rank": 2],
                ["name": "first", "rank": 1],
            ]
        )
    }
}
