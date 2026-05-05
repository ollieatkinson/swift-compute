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

extension Comparison: DirectComputeKeyword {
    static func computeDirectly(from input: JSON) throws -> JSON {
        guard case .object(let object) = input else {
            return try JSON.decoded(Comparison.self, from: input).compute()
        }
        if let operands = object["match"] {
            return try compare(operands, string: { lhs, rhs in
                lhs.range(of: rhs, options: NSString.CompareOptions.regularExpression) != nil
            })
        }
        if let operands = object["equal"] {
            return try equal(operands)
        }
        if let operands = object["less"] {
            return try ordered(operands, string: <, number: <)
        }
        if let operands = object["greater"] {
            return try ordered(operands, string: >, number: >)
        }
        if let operands = object["less_or_equal"] {
            return try ordered(operands, string: <=, number: <=)
        }
        if let operands = object["greater_or_equal"] {
            return try ordered(operands, string: >=, number: >=)
        }
        return .bool(false)
    }

    private static func compare(
        _ operands: JSON,
        _ predicate: (JSON, JSON) -> Bool
    ) throws -> JSON {
        guard let pair = operandPair(from: operands) else {
            return try JSON.decoded(Comparison.self, from: ["equal": operands]).compute()
        }
        return .bool(predicate(pair.lhs, pair.rhs))
    }

    private static func equal(_ operands: JSON) throws -> JSON {
        guard let pair = operandPair(from: operands) else {
            return try JSON.decoded(Equal.self, from: operands).compute()
        }
        switch (pair.lhs, pair.rhs) {
        case (.null, .null),
             (.bool, .bool),
             (.int, .int),
             (.double, .double),
             (.string, .string):
            return .bool(pair.lhs == pair.rhs)
        case (.array, _), (.object, _), (_, .array), (_, .object):
            return try JSON.decoded(Equal.self, from: operands).compute()
        default:
            return .bool(false)
        }
    }

    private static func compare(
        _ operands: JSON,
        string predicate: (String, String) -> Bool
    ) throws -> JSON {
        guard let pair = operandPair(from: operands) else {
            return try JSON.decoded(Comparison.self, from: ["match": operands]).compute()
        }
        guard case .string(let lhs) = pair.lhs, case .string(let rhs) = pair.rhs else {
            return try JSON.decoded(Match.self, from: operands).compute()
        }
        return .bool(predicate(lhs, rhs))
    }

    private static func ordered(
        _ operands: JSON,
        string stringPredicate: (String, String) -> Bool,
        number numberPredicate: (Double, Double) -> Bool
    ) throws -> JSON {
        guard let pair = operandPair(from: operands) else {
            return try JSON.decoded(Operands.self, from: operands)
                .orderedComparison(string: stringPredicate, number: numberPredicate)
        }
        if case .string(let lhs) = pair.lhs, case .string(let rhs) = pair.rhs {
            return .bool(stringPredicate(lhs, rhs))
        }
        if let lhs = pair.lhs.numberValue, let rhs = pair.rhs.numberValue {
            return .bool(numberPredicate(lhs, rhs))
        }
        return try Operands(lhs: pair.lhs, rhs: pair.rhs)
            .orderedComparison(string: stringPredicate, number: numberPredicate)
    }

    private static func operandPair(from input: JSON) -> (lhs: JSON, rhs: JSON)? {
        guard case .object(let object) = input else { return nil }
        guard let lhs = object["lhs"], let rhs = object["rhs"] else { return nil }
        return (lhs, rhs)
    }
}

private extension JSON {
    var numberValue: Double? {
        switch self {
        case .int(let value):
            return Double(value)
        case .double(let value):
            return value
        case .null, .bool, .string, .array, .object:
            return nil
        }
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
