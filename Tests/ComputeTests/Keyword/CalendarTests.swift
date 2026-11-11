import Compute
import Foundation
import Testing

struct CalendarTests {
    @Test
    func repeated_hours_remain_distinct_and_intervals_compose_with_date_and_text() async throws {
        let hours = try await value(query("2026-10-25T00:00:00Z", "2026-10-25T02:00:00Z", unit: "hour", zone: "Europe/London"))
        let rows = try #require(hours.object?["intervals"]?.array)
        #expect(rows.count == 2)
        #expect(rows.first?.object?["end"] == rows.last?.object?["start"])
        let weeks = query("2026-10-24T12:00:00Z", "2026-10-26T00:00:00Z", unit: "week", zone: "Europe/London")
        let start = JSON.returns("date", ["since": ["epoch": JSON.returns("item", ["start"])]])
        let end = JSON.returns("date", ["since": ["epoch": JSON.returns("item", ["end"])]])
        let labels = JSON.returns("array_map", [
            "over": .returns("get", ["value": weeks, "path": ["intervals"]]),
            "copy": [["to": [], "value": [
                "label": .returns("text", ["from": ["date": ["value": start, "format": "d MMM", "time_zone": "Europe/London"]]]),
                "duration": .returns("seconds", ["from": start, "to": end]),
            ]]],
        ])
        let output = try await value(labels)
        #expect(output.array?.first?.object?["label"]?.string == "19 Oct")
        #expect(output.array?.first?.object?["duration"]?.double == 169.0 * 3600)
    }

    @Test(arguments: [
        ("2026-03-29T00:00:00Z", "2026-03-29T23:00:00Z", 23.0),
        ("2026-10-24T23:00:00Z", "2026-10-26T00:00:00Z", 25.0),
    ])
    func calendar_days_follow_dst_instead_of_fixed_seconds(start: String, end: String, hours: Double) async throws {
        let partition = try await value(query(start, end, unit: "day", zone: "Europe/London"))
        let intervals = try #require(partition.object?["intervals"]?.array)
        #expect(intervals.count == 1)
        let interval = try #require(intervals.first?.object)
        let lower = try #require(interval["start"]?.double)
        let upper = try #require(interval["end"]?.double)
        #expect(upper - lower == hours * 3600)
        #expect(partition.object?["time_zone"] == "Europe/London")
    }

    @Test
    func iso_weeks_cross_years_and_keep_partial_boundaries_without_an_extra_end_interval() async throws {
        let partition = try await value(query("2021-01-01T12:00:00Z", "2021-01-11T00:00:00Z", unit: "week"))
        let intervals = try #require(partition.object?["intervals"]?.array)
        #expect(intervals.count == 2)
        let first = try #require(intervals.first?.object?["start"]?.double)
        let last = try #require(intervals.last?.object?["end"]?.double)
        let formatter = ISO8601DateFormatter()
        #expect(first == formatter.date(from: "2020-12-28T00:00:00Z")?.timeIntervalSince1970)
        #expect(last == formatter.date(from: "2021-01-11T00:00:00Z")?.timeIntervalSince1970)
        #expect(partition.object?["first_weekday"] == 2)
        #expect(partition.object?["minimum_days_in_first_week"] == 4)
        let changedZone = try await value(query("2021-01-01T01:00:00Z", "2021-01-01T01:00:01Z", unit: "day", zone: "America/New_York"))
        let start = try #require(changedZone.object?["intervals"]?.array?.first?.object?["start"]?.double)
        #expect(start == formatter.date(from: "2020-12-31T05:00:00Z")?.timeIntervalSince1970)
    }

    @Test
    func empty_ranges_custom_week_policy_and_invalid_inputs_are_explicit() async throws {
        let empty = try await value(query("2026-11-10T12:00:00Z", "2026-11-10T12:00:00Z", unit: "week"))
        #expect(empty.object?["intervals"]?.array?.isEmpty == true)
        var request = try #require(query("2021-01-01T00:00:00Z", "2021-01-01T01:00:00Z", unit: "week").object?["{returns}"]?.object?["calendar"]?.object)
        request["identifier"] = "gregorian"
        request["first_weekday"] = 1
        request["minimum_days_in_first_week"] = 1
        let sunday = try await value(.returns("calendar", .object(request)))
        let lower = try #require(sunday.object?["intervals"]?.array?.first?.object?["start"]?.double)
        #expect(lower == ISO8601DateFormatter().date(from: "2020-12-27T00:00:00Z")?.timeIntervalSince1970)
        for (key, invalid): (String, JSON) in [("time_zone", "Unknown/Zone"), ("first_weekday", 0), ("minimum_days_in_first_week", 8), ("unit", "forever"), ("identifier", "unknown")] {
            var malformed = request
            malformed[key] = invalid
            await #expect(throws: (any Error).self) { try await value(.returns("calendar", .object(malformed))) }
        }
        await #expect(throws: (any Error).self) { try await value(query("2026-11-11T00:00:00Z", "2026-11-10T00:00:00Z", unit: "day")) }
    }

    private func query(_ from: String, _ to: String, unit: String, zone: String = "UTC") -> JSON {
        .returns("calendar", ["from": .returns("date", ["from": ["iso": .string(from)]]), "to": .returns("date", ["from": ["iso": .string(to)]]), "unit": .string(unit), "time_zone": .string(zone)])
    }
}
