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

    public func compute() throws -> JSON {
        if let match {
            return try match.compute()
        }
        if let equal {
            return try equal.compute()
        }
        if let less {
            return try less.compute()
        }
        if let greater {
            return try greater.compute()
        }
        if let less_or_equal {
            return try less_or_equal.compute()
        }
        if let greater_or_equal {
            return try greater_or_equal.compute()
        }
        return .bool(false)
    }
}

extension Keyword.Match: ComputeKeyword {
    public static let name = "match"

    public func compute() throws -> JSON {
        let lhs = try self.lhs.decode(String.self)
        let rhs = try self.rhs.decode(String.self)
        return .bool(lhs.range(of: rhs, options: NSString.CompareOptions.regularExpression) != nil)
    }
}

extension Keyword.Equal: ComputeKeyword {
    public static let name = "equal"

    public func compute() throws -> JSON {
        .bool(lhs == rhs)
    }
}

extension Keyword.Less: ComputeKeyword {
    public static let name = "less"

    public func compute() throws -> JSON {
        try orderedComparison(string: <, number: <)
    }
}

extension Keyword.Greater: ComputeKeyword {
    public static let name = "greater"

    public func compute() throws -> JSON {
        try orderedComparison(string: >, number: >)
    }
}

extension Keyword.LessOrEqual: ComputeKeyword {
    public static let name = "less_or_equal"

    public func compute() throws -> JSON {
        try orderedComparison(string: <=, number: <=)
    }
}

extension Keyword.GreaterOrEqual: ComputeKeyword {
    public static let name = "greater_or_equal"

    public func compute() throws -> JSON {
        try orderedComparison(string: >=, number: >=)
    }
}
