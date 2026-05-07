import Foundation

extension Keyword {
    public struct Comparison: Codable, Equatable, Sendable {
        public var match: Match?
        public var equal: Equal?
        public var less: Less?
        public var greater: Greater?
        public var less_or_equal: LessOrEqual?
        public var greater_or_equal: GreaterOrEqual?
    }

    public struct Match: Codable, Equatable, Sendable, OperandPair {
        @Computed public var lhs: JSON
        @Computed public var rhs: JSON
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

extension Keyword.Comparison: ComputeKeyword {
    public static let name = "comparison"

    public func compute(in frame: ComputeFrame) async throws -> JSON? {
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

extension Keyword.Match: ComputeKeyword {
    public static let name = "match"

    public func compute(in frame: ComputeFrame) async throws -> JSON? {
        let lhs = try await $lhs.compute(in: frame).decode(String.self)
        let rhs = try await $rhs.compute(in: frame).decode(String.self)
        return .bool(lhs.range(of: rhs, options: NSString.CompareOptions.regularExpression) != nil)
    }
}

extension Keyword.Equal: ComputeKeyword {
    public static let name = "equal"

    public func compute(in frame: ComputeFrame) async throws -> JSON? {
        let lhs = try await $lhs.compute(in: frame)
        let rhs = try await $rhs.compute(in: frame)
        return .bool(lhs == rhs)
    }
}

extension Keyword.Less: ComputeKeyword {
    public static let name = "less"

    public func compute(in frame: ComputeFrame) async throws -> JSON? {
        try await computedOperands(lhs: $lhs, rhs: $rhs, in: frame).orderedComparison(string: <, number: <)
    }
}

extension Keyword.Greater: ComputeKeyword {
    public static let name = "greater"

    public func compute(in frame: ComputeFrame) async throws -> JSON? {
        try await computedOperands(lhs: $lhs, rhs: $rhs, in: frame).orderedComparison(string: >, number: >)
    }
}

extension Keyword.LessOrEqual: ComputeKeyword {
    public static let name = "less_or_equal"

    public func compute(in frame: ComputeFrame) async throws -> JSON? {
        try await computedOperands(lhs: $lhs, rhs: $rhs, in: frame).orderedComparison(string: <=, number: <=)
    }
}

extension Keyword.GreaterOrEqual: ComputeKeyword {
    public static let name = "greater_or_equal"

    public func compute(in frame: ComputeFrame) async throws -> JSON? {
        try await computedOperands(lhs: $lhs, rhs: $rhs, in: frame).orderedComparison(string: >=, number: >=)
    }
}
