import _JSON
import Foundation

public extension Compute.Keyword {
    /// Enumerates native calendar intervals, including partially covered ends.
    /// Output dates are Unix seconds; ranges are half-open, without fixed-day arithmetic.
    struct Calendar: Codable, Equatable, Sendable {
        public static let name = "calendar"
        @Computed public var from: Foundation.Date
        @Computed public var to: Foundation.Date
        @Computed public var unit: Unit
        @Computed public var identifier: Identifier?
        @Computed public var time_zone: String?
        @Computed public var first_weekday: Int?
        @Computed public var minimum_days_in_first_week: Int?

        public enum Identifier: String, Codable, Sendable {
            case iso8601, gregorian
        }

        public enum Unit: String, Codable, Sendable {
            case hour, day, week, month, year
            fileprivate var component: Foundation.Calendar.Component {
                switch self {
                case .hour: .hour
                case .day: .day
                case .week: .weekOfYear
                case .month: .month
                case .year: .year
                }
            }
        }
    }
}

extension Compute.Keyword.Calendar: Compute.OpaqueOutputKeywordDefinition {
    public func compute(in frame: Compute.Frame) async throws -> JSON? {
        let from = try await $from.compute(in: frame)
        let to = try await $to.compute(in: frame)
        guard from.timeIntervalSince1970.isFinite, to.timeIntervalSince1970.isFinite, from <= to else {
            throw JSONError("Calendar range requires finite dates with from <= to")
        }
        let identifier = try await $identifier.compute(in: frame) ?? .iso8601
        let zone = try await $time_zone.compute(in: frame) ?? TimeZone.current.identifier
        guard let timeZone = TimeZone(identifier: zone) else { throw JSONError("Unknown time zone \(zone)") }
        var calendar = Foundation.Calendar(identifier: identifier == .iso8601 ? .iso8601 : .gregorian)
        calendar.locale = Locale(identifier: "en_US_POSIX")
        calendar.timeZone = timeZone
        // Explicit defaults make week policy independent of the machine's locale.
        let firstWeekday = try await $first_weekday.compute(in: frame) ?? (identifier == .iso8601 ? 2 : 1)
        let minimumDays = try await $minimum_days_in_first_week.compute(in: frame) ?? (identifier == .iso8601 ? 4 : 1)
        guard (1 ... 7).contains(firstWeekday), (1 ... 7).contains(minimumDays) else {
            throw JSONError("Calendar week policy values must be between 1 and 7")
        }
        calendar.firstWeekday = firstWeekday
        calendar.minimumDaysInFirstWeek = minimumDays
        let unit = try await $unit.compute(in: frame)
        var intervals: [JSON] = []
        var cursor = from
        while cursor < to {
            try Task.checkCancellation()
            guard let interval = calendar.dateInterval(of: unit.component, for: cursor), interval.end > cursor else {
                throw JSONError("Calendar could not advance the requested interval")
            }
            intervals.append(["start": .double(interval.start.timeIntervalSince1970), "end": .double(interval.end.timeIntervalSince1970)])
            cursor = interval.end
        }
        return [
            "identifier": .string(identifier.rawValue), "time_zone": .string(zone),
            "unit": .string(unit.rawValue), "first_weekday": .int(calendar.firstWeekday),
            "minimum_days_in_first_week": .int(calendar.minimumDaysInFirstWeek),
            "from": .double(from.timeIntervalSince1970), "to": .double(to.timeIntervalSince1970),
            "intervals": .array(intervals),
        ]
    }
}
