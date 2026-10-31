import Compute
import Foundation
import Testing

@Suite struct MappingDataTests {
    @Test(arguments: ["map", "array_map"])
    func copies_paths_without_collapsing_missing_and_null(keyword: String) async throws {
        let record: JSON = ["name": "Dorothy", "email": .null]
        let copies: JSON = [
            ["from": ["name"], "to": ["profile", "name"], "required": true],
            ["from": ["email"], "to": ["profile", "email"]],
            ["from": ["missing"], "to": ["profile", "absent"]],
            ["value": JSON.returns("text", ["from": ["joining": ["array": ["Hello ", JSON.returns("item", ["name"])]]]]), "to": ["greeting"]],
        ]
        let arguments: JSON = keyword == "map" ? ["src": record, "dst": [:], "copy": copies]
            : ["over": [record], "copy": copies]
        let expected: JSON = ["profile": ["name": "Dorothy", "email": .null], "greeting": "Hello Dorothy"]
        try await expect(.returns(keyword, arguments), equals: keyword == "map" ? expected : [expected])
        await expectJSONError(containing: "Missing map source") {
            _ = try await value(.returns(keyword, keyword == "map"
                ? ["src": record, "copy": [["from": ["missing"], "to": ["name"], "required": true]]]
                : ["over": [record], "copy": [["from": ["missing"], "to": ["name"], "required": true]]]))
        }
    }

    @Test func rejects_ambiguous_copy_instructions() async throws {
        await expectJSONError(containing: "either from or value") {
            _ = try await value(.returns("map", ["src": [:], "copy": [["from": ["name"], "value": "other", "to": ["name"]]]]))
        }
    }

    @Test func http_and_mapping_keep_expression_shaped_response_data_inert() async throws {
        let data: JSON = ["id": "p1", "title": JSON.returns("error", ["message": "Untrusted response data"])]
        let http = Compute.Keyword.HTTP.Function { _ in
            .init(data: try JSONEncoder().encode(data), status: 200)
        }
        let response = JSON.returns("http", ["request": ["url": "https://example.com/programmes"]])
        let expression = JSON.returns("map", ["src": response, "dst": [:], "copy": [
            ["from": ["body", "id"], "to": ["id"], "required": true],
            ["value": JSON.returns("item", ["body", "title"]), "to": ["title"]],
        ]])
        #expect(try await value(expression, functions: [http]) == data)
    }

    @Test func formats_and_splits_dates_with_explicit_offsets_and_time_zones() async throws {
        let date = JSON.returns("date", ["since": ["epoch": 1_704_067_200], "offset": 86_400])
        let formatted = JSON.returns("text", ["from": ["date": ["value": date, "format": "yyyy-MM-dd'T'HH:mm:ss.SSS'Z'"]]])
        try await expect(formatted, equals: "2024-01-02T00:00:00.000Z")
        try await expect(.returns("text", ["from": ["splitting": ["value": formatted, "separator": "T"]]]),
            equals: ["2024-01-02", "00:00:00.000Z"])
        try await expect(.returns("text", ["from": ["date": ["value": date, "format": "yyyyMMdd", "time_zone": "America/New_York"]]]), equals: "20240101")
        await expectJSONError(containing: "Unknown time zone") {
            _ = try await value(.returns("text", ["from": ["date": ["value": date, "format": "yyyy", "time_zone": "invalid"]]]))
        }
        await expectJSONError(containing: "non-empty text separator") {
            _ = try await value(.returns("text", ["from": ["splitting": ["value": "abc", "separator": ""]]]))
        }
    }
}

@Suite struct SelectedDataTests {
    private static let data: JSON = ["id": "p1", "title": JSON.returns("error", ["message": "Data is inert"])]
    private static var cases: [(String, JSON, JSON)] {
        let item = JSON.returns("item", [])
        let array = JSON.returns("literal", ["value": [data]])
        return [
            ("item", [], data),
            ("this", ["value": item], data),
            ("either", [["value": item]], data),
            ("array_filter", ["array": array, "predicate": true], [data]),
            ("array_map", ["over": array], [data]),
            ("array_group", ["array": array, "into": ["counts": [1]]], [[data]]),
            ("array_reduce", ["array": array, "initial": .null, "next": JSON.returns("item", ["item"])], data),
            ("array_slice", ["of": array, "from": 0, "to": 1], [data]),
            ("array_sort", ["array": array], [data]),
            ("array_subscript", ["of": array, "index": 0], data),
            ("array_zip", ["together": [array]], [[data]]),
        ]
    }

    @Test(arguments: cases) func selected_data_is_not_executed_again(keyword: String, input: JSON, expected: JSON) async throws {
        try await expect(.returns(keyword, input), in: Compute.Context(item: Self.data), equals: expected)
    }
}
