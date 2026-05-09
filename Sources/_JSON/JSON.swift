public typealias JSONValue = any Hashable & Sendable & Codable

public struct JSON: Hashable, Sendable, Codable {
    public typealias Object = [String: JSON]
    public typealias Array = [JSON]

    public struct Null: Hashable, Sendable, Codable {
        public init() { }
    }

    public private(set) var rawValue: JSONValue

    public init(_ value: JSON) {
        self = value
    }

    public init<Value>(_ value: Value) where Value: Hashable & Sendable & Codable {
        if let value = value as? JSON {
            self = value
        } else {
            self.rawValue = value
        }
    }

    public static var null: JSON {
        JSON(Null())
    }

    public static func bool(_ value: Bool) -> JSON {
        JSON(value)
    }

    public static func int(_ value: Int) -> JSON {
        JSON(value)
    }

    public static func double(_ value: Double) -> JSON {
        JSON(value)
    }

    public static func string(_ value: String) -> JSON {
        JSON(value)
    }

    public static func array(_ values: Array) -> JSON {
        JSON(values)
    }

    public static func object(_ values: Object) -> JSON {
        JSON(values)
    }
}

public extension Dictionary where Key == String, Value == JSON {
    var sortedEntries: [(key: String, value: JSON)] {
        sorted { lhs, rhs in lhs.key < rhs.key }
    }
}

public extension JSON {
    var isNull: Bool {
        rawValue is Null
    }

    var bool: Bool? {
        rawValue as? Bool
    }

    var int: Int? {
        rawValue as? Int
    }

    var double: Double? {
        switch rawValue {
        case let value as Double:
            return value
        case let value as Float:
            return Double(value)
        default:
            return nil
        }
    }

    var string: String? {
        rawValue as? String
    }

    var array: Array? {
        rawValue as? Array
    }

    var object: Object? {
        rawValue as? Object
    }

    var count: Int {
        if isNull {
            return 0
        }
        if let string {
            return string.count
        }
        if let array {
            return array.count
        }
        if let object {
            return object.count
        }
        return 1
    }
}
