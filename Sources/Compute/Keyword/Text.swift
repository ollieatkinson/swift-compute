import _JSON
import Foundation
extension Compute.Keyword {
    public struct Text: Codable, Equatable, Sendable {
        public static let name = "text"

        public let from: From

        public struct From: Codable, Equatable, Sendable {
            public let joining: Joining?
            public let splitting: Splitting?
            public let date: DateText?
            public let number: NumberText?
        }

        public struct Splitting: Codable, Equatable, Sendable {
            @Computed public var value: String
            @Computed public var separator: String
        }

        public struct DateText: Codable, Equatable, Sendable {
            @Computed public var value: Foundation.Date
            @Computed public var format: String
            @Computed public var time_zone: String?
        }

        public struct NumberText: Codable, Equatable, Sendable {
            @Computed public var value: Double
            @Computed public var currency: String?
            @Computed public var locale: String?
        }

        public struct Joining: Codable, Equatable, Sendable {
            @Computed public var array: [String]
            @Computed public var separator: String?
            @Computed public var terminator: String?
        }
    }
}

extension Compute.Keyword.Text: Compute.KeywordDefinition {
    public func compute(in frame: Compute.Frame) async throws -> JSON? {
        if let joining = from.joining {
            return try await joining.compute(in: frame)
        }
        if let splitting = from.splitting {
            let value = try await splitting.$value.compute(in: frame)
            let separator = try await splitting.$separator.compute(in: frame)
            guard !separator.isEmpty else { throw JSONError("Expected a non-empty text separator") }
            return .array(value.components(separatedBy: separator).map(JSON.string))
        }
        if let date = from.date {
            let value = try await date.$value.compute(in: frame)
            let pattern = try await date.$format.compute(in: frame)
            let zone = try await date.$time_zone.compute(in: frame) ?? "UTC"
            guard let timeZone = TimeZone(identifier: zone) else { throw JSONError("Unknown time zone \(zone)") }
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.calendar = Calendar(identifier: .gregorian)
            formatter.timeZone = timeZone
            formatter.dateFormat = pattern
            return .string(formatter.string(from: value))
        }
        if let number = from.number {
            guard #available(macOS 12, iOS 15, tvOS 15, watchOS 8, *) else {
                throw JSONError("Number text requires Foundation format styles")
            }
            let value = try await number.$value.compute(in: frame)
            guard value.isFinite else { throw JSONError("Expected a finite number") }
            let locale = Locale(identifier: try await number.$locale.compute(in: frame) ?? "en_US_POSIX")
            if let currency = try await number.$currency.compute(in: frame) {
                guard !currency.isEmpty else { throw JSONError("Expected a currency code") }
                return .string(value.formatted(.currency(code: currency).locale(locale)))
            }
            return .string(value.formatted(.number.locale(locale)))
        }
        throw JSONError("Expected text formatter")
    }
}
extension Compute.Keyword.Text.Joining {
    func compute(in frame: Compute.Frame) async throws -> JSON {
        let array = try await $array.compute(in: frame)
        let separator = try await $separator.compute(in: frame) ?? ""
        let terminator = try await $terminator.compute(in: frame) ?? ""
        return .string(array.joined(separator: separator).appending(terminator))
    }
}
