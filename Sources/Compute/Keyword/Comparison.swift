import _JSON
import Foundation

extension Compute.Keyword {
    public struct Comparison: Codable, Equatable, Sendable {
        public var match: Match?
        public var equal: Equal?
        public var less: Less?
        public var greater: Greater?
        public var less_or_equal: LessOrEqual?
        public var greater_or_equal: GreaterOrEqual?
        public var `is`: Is?

        private enum CodingKeys: String, CodingKey {
            case match, equal, less, greater, less_or_equal, greater_or_equal, `is`
        }
    }

    public struct Match: Codable, Equatable, Sendable {
        @Computed public var lhs: String
        @Computed public var rhs: String
    }

    public struct Equal: Codable, Equatable, Sendable, OperandPair {
        @Computed public var lhs: JSON
        @Computed public var rhs: JSON
    }

    public struct Less: Codable, Equatable, Sendable, OperandPair {
        @Computed public var lhs: JSON
        @Computed public var rhs: JSON
    }

    public struct Greater: Codable, Equatable, Sendable, OperandPair {
        @Computed public var lhs: JSON
        @Computed public var rhs: JSON
    }

    public struct LessOrEqual: Codable, Equatable, Sendable, OperandPair {
        @Computed public var lhs: JSON
        @Computed public var rhs: JSON
    }

    public struct GreaterOrEqual: Codable, Equatable, Sendable, OperandPair {
        @Computed public var lhs: JSON
        @Computed public var rhs: JSON
    }
}

extension Compute.Keyword.Comparison {
    public init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        match = try values.decodeIfPresent(Compute.Keyword.Match.self, forKey: .match)
        equal = try values.decodeIfPresent(Compute.Keyword.Equal.self, forKey: .equal)
        less = try values.decodeIfPresent(Compute.Keyword.Less.self, forKey: .less)
        greater = try values.decodeIfPresent(Compute.Keyword.Greater.self, forKey: .greater)
        less_or_equal = try values.decodeIfPresent(Compute.Keyword.LessOrEqual.self, forKey: .less_or_equal)
        greater_or_equal = try values.decodeIfPresent(Compute.Keyword.GreaterOrEqual.self, forKey: .greater_or_equal)
        // The in-memory decoder's decodeIfPresent can swallow invalid input.
        // A supplied type query must validate its required operands and kind.
        self.is = try values.contains(.is) && !values.decodeNil(forKey: .is)
            ? values.decode(Compute.Keyword.Is.self, forKey: .is) : nil
    }
}

extension Compute.Keyword.Comparison: Compute.KeywordDefinition {
    public static let name = "comparison"

    public func compute(in frame: Compute.Frame) async throws -> JSON? {
        if let match {
            return try await match.compute(in: frame)
        }
        if let equal {
            return try await equal.compute(in: frame)
        }
        if let less {
            return try await less.compute(in: frame)
        }
        if let greater {
            return try await greater.compute(in: frame)
        }
        if let less_or_equal {
            return try await less_or_equal.compute(in: frame)
        }
        if let greater_or_equal {
            return try await greater_or_equal.compute(in: frame)
        }
        if let predicate = self.is {
            return try await predicate.compute(in: frame)
        }
        return .bool(false)
    }
}

extension Compute.Keyword.Match: Compute.KeywordDefinition {
    public static let name = "match"

    public func compute(in frame: Compute.Frame) async throws -> JSON? {
        let lhs = try await $lhs.compute(in: frame)
        let rhs = try await $rhs.compute(in: frame)
        return .bool(lhs.range(of: rhs, options: NSString.CompareOptions.regularExpression) != nil)
    }
}

extension Compute.Keyword.Equal: Compute.KeywordDefinition {
    public static let name = "equal"

    public func compute(in frame: Compute.Frame) async throws -> JSON? {
        let lhs = try await $lhs.compute(in: frame)
        let rhs = try await $rhs.compute(in: frame)
        return .bool(lhs == rhs)
    }
}

extension Compute.Keyword.Less: Compute.KeywordDefinition {
    public static let name = "less"

    public func compute(in frame: Compute.Frame) async throws -> JSON? {
        try await computedOperands(lhs: $lhs, rhs: $rhs, in: frame)
            .orderedComparison(string: <, number: <)
    }
}

extension Compute.Keyword.Greater: Compute.KeywordDefinition {
    public static let name = "greater"

    public func compute(in frame: Compute.Frame) async throws -> JSON? {
        try await computedOperands(lhs: $lhs, rhs: $rhs, in: frame)
            .orderedComparison(string: >, number: >)
    }
}

extension Compute.Keyword.LessOrEqual: Compute.KeywordDefinition {
    public static let name = "less_or_equal"

    public func compute(in frame: Compute.Frame) async throws -> JSON? {
        try await computedOperands(lhs: $lhs, rhs: $rhs, in: frame)
            .orderedComparison(string: <=, number: <=)
    }
}

extension Compute.Keyword.GreaterOrEqual: Compute.KeywordDefinition {
    public static let name = "greater_or_equal"

    public func compute(in frame: Compute.Frame) async throws -> JSON? {
        try await computedOperands(lhs: $lhs, rhs: $rhs, in: frame)
            .orderedComparison(string: >=, number: >=)
    }
}
