import _JSON
import Foundation

extension Compute.Keyword {
    public struct Date: Codable, Equatable, Sendable {
        public static let name = "date"

        @Computed public var since: Since?
        @Computed public var from: From?
        @Computed public var offset: TimeInterval?

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
            return JSON(Foundation.Date(timeIntervalSince1970: epoch).addingTimeInterval(try await $offset.compute(in: frame) ?? 0))
        }

    out:
        if let from = try await $from.compute(in: frame), let iso = try await from.$iso.compute(in: frame["from"]) {
            guard let date = Self.date(from: iso) else { break out }
            return JSON(date.addingTimeInterval(try await $offset.compute(in: frame) ?? 0))
        }

        throw JSONError(
            """
            Not a valid date, must be a time interval from epoch or an ISO 8601 timestamp with a time zone
            """
        )
    }

    private static func date(from source: String) -> Foundation.Date? {
        if #available(macOS 12, iOS 15, tvOS 15, watchOS 8, *) {
            let fractional = Foundation.Date.ISO8601FormatStyle(timeZoneSeparator: .colon, includingFractionalSeconds: true)
            if let date = (try? fractional.parse(source))
                ?? (try? Foundation.Date.ISO8601FormatStyle(timeZoneSeparator: .colon).parse(source)) {
                return date
            }
        }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: source) { return date }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: source)
    }
}
