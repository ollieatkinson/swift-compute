import _JSON
import Foundation

extension Compute.Keyword {
    public struct Seconds: Codable, Equatable, Sendable {
        public static let name = "seconds"

        @Computed public var from: Foundation.Date
        @Computed public var to: Foundation.Date
    }
}

extension Compute.Keyword.Seconds: Compute.KeywordDefinition {
    public func compute(in frame: Compute.Frame) async throws -> JSON? {
        let from = try await $from.compute(in: frame).timeIntervalSinceReferenceDate
        let to = try await $to.compute(in: frame).timeIntervalSinceReferenceDate
        return .double(to - from)
    }
}
