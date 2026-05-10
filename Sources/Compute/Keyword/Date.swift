import _JSON
import Foundation

extension Compute.Keyword {
    public struct Date: Codable, Equatable, Sendable {
        public static let name = "date"

        @Computed public var since: Since?
        @Computed public var from: From?

        public struct Since: Codable, Equatable, Sendable {
            @Computed public var epoch: TimeInterval?
        }

        public struct From: Codable, Equatable, Sendable {
            @Computed public var iso: String?
        }
    }
}

extension Compute.Keyword.Date: Compute.KeywordDefinition {
    public func compute(in frame: Compute.Frame) async throws -> JSON? {
        if let since = try await $since.compute(in: frame), let epoch = try await since.$epoch.compute(in: frame["since"]) {
            return JSON(Foundation.Date(timeIntervalSince1970: epoch))
        }

    out:
        if let from = try await $from.compute(in: frame), let iso = try await from.$iso.compute(in: frame["from"]) {
            guard let date = Self.isoDateFormatter.date(from: iso) else { break out }
            return JSON(date)
        }

        throw JSONError(
            """
            Not a valid date, must be a time interval from epoch or an RFC 8601 date string with fractional seconds
            """
        )
    }

    private static var isoDateFormatter: ISO8601DateFormatter {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }
}
