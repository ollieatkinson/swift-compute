import _JSON
import Foundation
extension Compute.Keyword {
    public struct Contains: Codable, Equatable, Sendable {
        @Computed public var lhs: JSON
        @Computed public var rhs: JSON
        @Computed public var case_sensitive: JSON?
    }
}

extension Compute.Keyword.Contains: Compute.KeywordDefinition {
    public static let name = "contains"

    public func compute(in frame: Compute.Frame) async throws -> JSON? {
        let lhs = try await $lhs.compute(in: frame)
        let rhs = try await $rhs.compute(in: frame)
        let option = try await $case_sensitive.compute(in: frame)
        if let option, Swift.type(of: option.rawValue) != Bool.self {
            throw JSONError("contains case_sensitive must be a boolean")
        }
        let caseSensitive = option?.bool
        if let lhs = lhs.string {
            guard let rhs = rhs.string else {
                throw JSONError("contains rhs must be a string when lhs is a string")
            }
            if caseSensitive == false {
                return .bool(rhs.isEmpty || lhs.range(of: rhs, options: .caseInsensitive) != nil)
            }
            return .bool(lhs.contains(rhs))
        }
        if let lhs = lhs.array {
            guard caseSensitive == nil else {
                throw JSONError("contains case_sensitive applies only to strings")
            }
            return .bool(lhs.contains(rhs))
        }
        throw JSONError("contains lhs must be a string or array")
    }
}
