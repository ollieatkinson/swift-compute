import Foundation

extension Keyword {
    public struct Comparison: Codable, Equatable, Sendable {
        public var match: Match?
        public var equal: Equal?
        public var less: Less?
        public var greater: Greater?
        public var less_or_equal: LessOrEqual?
        public var greater_or_equal: GreaterOrEqual?

        public init(
            match: Match? = nil,
            equal: Equal? = nil,
            less: Less? = nil,
            greater: Greater? = nil,
            less_or_equal: LessOrEqual? = nil,
            greater_or_equal: GreaterOrEqual? = nil
        ) {
            self.match = match
            self.equal = equal
            self.less = less
            self.greater = greater
            self.less_or_equal = less_or_equal
            self.greater_or_equal = greater_or_equal
        }
    }

    public struct Match: Codable, Equatable, Sendable, OperandPair {
        public let lhs: JSON
        public let rhs: JSON

        public init(lhs: JSON, rhs: JSON) {
            self.lhs = lhs
            self.rhs = rhs
        }
    }

    public struct Equal: Codable, Equatable, Sendable, OperandPair {
        public let lhs: JSON
        public let rhs: JSON

        public init(lhs: JSON, rhs: JSON) {
            self.lhs = lhs
            self.rhs = rhs
        }
    }

    public struct Less: Codable, Equatable, Sendable, OperandPair {
        public let lhs: JSON
        public let rhs: JSON

        public init(lhs: JSON, rhs: JSON) {
            self.lhs = lhs
            self.rhs = rhs
        }
    }

    public struct Greater: Codable, Equatable, Sendable, OperandPair {
        public let lhs: JSON
        public let rhs: JSON

        public init(lhs: JSON, rhs: JSON) {
            self.lhs = lhs
            self.rhs = rhs
        }
    }

    public struct LessOrEqual: Codable, Equatable, Sendable, OperandPair {
        public let lhs: JSON
        public let rhs: JSON

        public init(lhs: JSON, rhs: JSON) {
            self.lhs = lhs
            self.rhs = rhs
        }
    }

    public struct GreaterOrEqual: Codable, Equatable, Sendable, OperandPair {
        public let lhs: JSON
        public let rhs: JSON

        public init(lhs: JSON, rhs: JSON) {
            self.lhs = lhs
            self.rhs = rhs
        }
    }
}

extension Keyword.Comparison: ComputeKeyword {
    public static let name = "comparison"

    public func compute(in frame: ComputeFrame) async throws -> JSON? {
        if let match {
            return try await match.compute(in: frame["match"])
        }
        if let equal {
            return try await equal.compute(in: frame["equal"])
        }
        if let less {
            return try await less.compute(in: frame["less"])
        }
        if let greater {
            return try await greater.compute(in: frame["greater"])
        }
        if let less_or_equal {
            return try await less_or_equal.compute(in: frame["less_or_equal"])
        }
        if let greater_or_equal {
            return try await greater_or_equal.compute(in: frame["greater_or_equal"])
        }
        return .bool(false)
    }
}

extension Keyword.Match: ComputeKeyword {
    public static let name = "match"

    public func compute(in frame: ComputeFrame) async throws -> JSON? {
        let operands = try await computed(in: frame)
        let lhs = try operands.lhs.decode(String.self)
        let rhs = try operands.rhs.decode(String.self)
        return .bool(lhs.range(of: rhs, options: NSString.CompareOptions.regularExpression) != nil)
    }
}

extension Keyword.Equal: ComputeKeyword {
    public static let name = "equal"

    public func compute(in frame: ComputeFrame) async throws -> JSON? {
        let operands = try await computed(in: frame)
        return .bool(operands.lhs == operands.rhs)
    }
}

extension Keyword.Less: ComputeKeyword {
    public static let name = "less"

    public func compute(in frame: ComputeFrame) async throws -> JSON? {
        try await computed(in: frame).orderedComparison(string: <, number: <)
    }
}

extension Keyword.Greater: ComputeKeyword {
    public static let name = "greater"

    public func compute(in frame: ComputeFrame) async throws -> JSON? {
        try await computed(in: frame).orderedComparison(string: >, number: >)
    }
}

extension Keyword.LessOrEqual: ComputeKeyword {
    public static let name = "less_or_equal"

    public func compute(in frame: ComputeFrame) async throws -> JSON? {
        try await computed(in: frame).orderedComparison(string: <=, number: <=)
    }
}

extension Keyword.GreaterOrEqual: ComputeKeyword {
    public static let name = "greater_or_equal"

    public func compute(in frame: ComputeFrame) async throws -> JSON? {
        try await computed(in: frame).orderedComparison(string: >=, number: >=)
    }
}
