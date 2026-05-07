import Foundation

extension Compute.Keyword {
    public struct Comparison: Codable, Equatable, Sendable {
        public var match: Match?
        public var equal: Equal?
        public var less: Less?
        public var greater: Greater?
        public var less_or_equal: LessOrEqual?
        public var greater_or_equal: GreaterOrEqual?
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
        try await computedOperands(lhs: $lhs, rhs: $rhs, in: frame).orderedComparison(string: <, number: <)
    }
}

extension Compute.Keyword.Greater: Compute.KeywordDefinition {
    public static let name = "greater"

    public func compute(in frame: Compute.Frame) async throws -> JSON? {
        try await computedOperands(lhs: $lhs, rhs: $rhs, in: frame).orderedComparison(string: >, number: >)
    }
}

extension Compute.Keyword.LessOrEqual: Compute.KeywordDefinition {
    public static let name = "less_or_equal"

    public func compute(in frame: Compute.Frame) async throws -> JSON? {
        try await computedOperands(lhs: $lhs, rhs: $rhs, in: frame).orderedComparison(string: <=, number: <=)
    }
}

extension Compute.Keyword.GreaterOrEqual: Compute.KeywordDefinition {
    public static let name = "greater_or_equal"

    public func compute(in frame: Compute.Frame) async throws -> JSON? {
        try await computedOperands(lhs: $lhs, rhs: $rhs, in: frame).orderedComparison(string: >=, number: >=)
    }
}
