import Foundation

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

    public static func match(lhs: JSON, rhs: JSON) -> Comparison {
        Comparison(match: Match(lhs: lhs, rhs: rhs))
    }

    public static func equal(lhs: JSON, rhs: JSON) -> Comparison {
        Comparison(equal: Equal(lhs: lhs, rhs: rhs))
    }

    public static func less(lhs: JSON, rhs: JSON) -> Comparison {
        Comparison(less: Less(lhs: lhs, rhs: rhs))
    }

    public static func greater(lhs: JSON, rhs: JSON) -> Comparison {
        Comparison(greater: Greater(lhs: lhs, rhs: rhs))
    }

    public static func lessOrEqual(lhs: JSON, rhs: JSON) -> Comparison {
        Comparison(less_or_equal: LessOrEqual(lhs: lhs, rhs: rhs))
    }

    public static func greaterOrEqual(lhs: JSON, rhs: JSON) -> Comparison {
        Comparison(greater_or_equal: GreaterOrEqual(lhs: lhs, rhs: rhs))
    }
}

extension Comparison: ComputeKeyword {
    public static let keyword = "comparison"

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

public struct Match: Codable, Equatable, Sendable, OperandPair {
    public let lhs: JSON
    public let rhs: JSON

    public init(lhs: JSON, rhs: JSON) {
        self.lhs = lhs
        self.rhs = rhs
    }
}

extension Match: ComputeKeyword {
    public static let keyword = "match"

    public func compute() throws -> JSON {
        let lhs = try self.lhs.decode(String.self)
        let rhs = try self.rhs.decode(String.self)
        return .bool(lhs.range(of: rhs, options: NSString.CompareOptions.regularExpression) != nil)
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

extension Equal: ComputeKeyword {
    public static let keyword = "equal"

    public func compute() throws -> JSON {
        .bool(lhs == rhs)
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

extension Less: ComputeKeyword {
    public static let keyword = "less"

    public func compute() throws -> JSON {
        try orderedComparison(string: <, number: <)
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

extension Greater: ComputeKeyword {
    public static let keyword = "greater"

    public func compute() throws -> JSON {
        try orderedComparison(string: >, number: >)
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

extension LessOrEqual: ComputeKeyword {
    public static let keyword = "less_or_equal"

    public func compute() throws -> JSON {
        try orderedComparison(string: <=, number: <=)
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

extension GreaterOrEqual: ComputeKeyword {
    public static let keyword = "greater_or_equal"

    public func compute() throws -> JSON {
        try orderedComparison(string: >=, number: >=)
    }
}
