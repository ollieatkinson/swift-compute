import AnyCoding
import Foundation

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

    public init(jsonObject value: Any?) throws {
        guard let value = Self.unwrapped(value), !(value is NSNull), !(value is Null) else {
            self = .null
            return
        }

        switch Swift.type(of: value) {
        case is Bool.Type:
            self.init(value as! Bool)
        case is Int.Type:
            self.init(value as! Int)
        case is Int8.Type:
            self.init(Int(value as! Int8))
        case is Int16.Type:
            self.init(Int(value as! Int16))
        case is Int32.Type:
            self.init(Int(value as! Int32))
        case is Int64.Type:
            self = Self.integer(value as! Int64)
        case is UInt.Type:
            self = Self.unsignedInteger(value as! UInt)
        case is UInt8.Type:
            self.init(Int(value as! UInt8))
        case is UInt16.Type:
            self.init(Int(value as! UInt16))
        case is UInt32.Type:
            self = Self.unsignedInteger(value as! UInt32)
        case is UInt64.Type:
            self = Self.unsignedInteger(value as! UInt64)
        case is Float.Type:
            self.init(Double(value as! Float))
        case is Double.Type:
            self.init(value as! Double)
        default:
            switch value {
            case let value as NSNumber:
                self = Self.number(value)
            case let value as String:
                self.init(value)
            case let value as JSON:
                self = value
            case let values as Array:
                self.init(values)
            case let values as Object:
                self.init(values)
            case let values as [Any]:
                self.init(try values.map(JSON.init(jsonObject:)))
            case let values as [String: Any]:
                self.init(try values.mapValues(JSON.init(jsonObject:)))
            default:
                throw JSONError("Unsupported JSON value \(String(describing: value))")
            }
        }
    }

    public init(data: Data, options: JSONSerialization.ReadingOptions = [.fragmentsAllowed]) throws {
        try self.init(jsonObject: JSONSerialization.jsonObject(with: data, options: options))
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

    public static func returns(_ keyword: String, _ argument: JSON, default fallback: JSON? = nil) -> JSON {
        var object: Object = [
            "{returns}": .object([keyword: argument]),
        ]
        if let fallback {
            object["default"] = fallback
        }
        return .object(object)
    }
}

public extension Dictionary where Key == String, Value == JSON {
    var sortedEntries: [(key: String, value: JSON)] {
        sorted { lhs, rhs in lhs.key < rhs.key }
    }
}

public extension JSON {
    var any: Any {
        Self.foundationValue(rawValue)
    }

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

    func asList() -> [JSON] {
        if isNull {
            return []
        }
        return array ?? [self]
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

    var stableDescription: String {
        var output = ""
        appendStableDescription(to: &output)
        return output
    }

    private func appendStableDescription(to output: inout String) {
        switch rawValue {
        case is Null:
            output += "null"
        case let value as Bool:
            output += "bool:"
            output += String(value)
        case let value as Int:
            output += "int:"
            output += String(value)
        case let value as Double:
            output += "double:"
            output += String(value)
        case let value as String:
            output += "string:"
            output += value
        case let values as Array:
            output += "["
            for index in values.indices {
                if index != values.startIndex {
                    output += ","
                }
                values[index].appendStableDescription(to: &output)
            }
            output += "]"
        case let object as Object:
            output += "{"
            for (index, entry) in object.sortedEntries.enumerated() {
                if index != 0 {
                    output += ","
                }
                output += entry.key
                output += ":"
                entry.value.appendStableDescription(to: &output)
            }
            output += "}"
        case let value:
            output += "fragment:"
            output += String(describing: value)
        }
    }

    func data(options: JSONSerialization.WritingOptions = [.fragmentsAllowed]) throws -> Data {
        let value = any
        guard JSONSerialization.isValidJSONObject([value]) else {
            throw JSONError("\(String(describing: self)) is not valid JSON.")
        }
        return try JSONSerialization.data(withJSONObject: value, options: options)
    }

    func prettyPrinted(options: JSONSerialization.WritingOptions = [.sortedKeys, .fragmentsAllowed]) throws -> String {
        try String(decoding: data(options: options.union(.prettyPrinted)), as: UTF8.self)
    }

    static func encoded(_ value: some Encodable) throws -> JSON {
        try JSON(jsonObject: AnyEncoder().encode(value))
    }

    static func decoded<Value: Decodable>(
        _ type: Value.Type = Value.self,
        from value: JSON
    ) throws -> Value {
        try AnyDecoder().decode(Value.self, from: value.any)
    }

    static func decoded(_ type: JSON.Type = JSON.self, from value: JSON) -> JSON {
        value
    }

    func decode<Value: Decodable>(_ type: Value.Type = Value.self) throws -> Value {
        try AnyDecoder().decode(Value.self, from: any)
    }

    func decode(_ type: JSON.Type = JSON.self) -> JSON {
        self
    }
}

extension JSON: ExpressibleByNilLiteral {
    public init(nilLiteral: ()) {
        self = .null
    }
}

extension JSON: ExpressibleByBooleanLiteral {
    public init(booleanLiteral value: Bool) {
        self.init(value)
    }
}

extension JSON: ExpressibleByIntegerLiteral {
    public init(integerLiteral value: Int) {
        self.init(value)
    }
}

extension JSON: ExpressibleByFloatLiteral {
    public init(floatLiteral value: Double) {
        self.init(value)
    }
}

extension JSON: ExpressibleByStringLiteral {
    public init(stringLiteral value: String) {
        self.init(value)
    }
}

extension JSON: ExpressibleByArrayLiteral {
    public init(arrayLiteral elements: JSON...) {
        self.init(elements)
    }
}

extension JSON: ExpressibleByDictionaryLiteral {
    public init(dictionaryLiteral elements: (String, JSON)...) {
        self.init(Dictionary(elements, uniquingKeysWith: { _, last in last }))
    }
}

public extension JSON {
    static func == (lhs: JSON, rhs: JSON) -> Bool {
        lhs.isEqual(to: rhs)
    }

    func hash(into hasher: inout Hasher) {
        switch rawValue {
        case is Null:
            hasher.combine(0)
        case let value as Bool:
            hasher.combine(1)
            hasher.combine(value)
        case let value as Int:
            hasher.combine(2)
            hasher.combine(value)
        case let value as Double:
            hasher.combine(3)
            hasher.combine(value)
        case let value as String:
            hasher.combine(4)
            hasher.combine(value)
        case let values as Array:
            hasher.combine(5)
            hasher.combine(values)
        case let object as Object:
            hasher.combine(6)
            for (key, value) in object.sortedEntries {
                hasher.combine(key)
                hasher.combine(value)
            }
        default:
            hasher.combine(7)
            hasher.combine(String(reflecting: Swift.type(of: rawValue)))
            hasher.combine(AnyHashable(rawValue))
        }
    }

    init(from decoder: Decoder) throws {
        if let decoder = decoder as? AnyDecoderProtocol {
            let value = Self.unwrapped(decoder.value)
            if value == nil || value is NSNull || value is Null {
                self = .null
                return
            }
        }

        if let container = try? decoder.singleValueContainer() {
            if container.decodeNil() {
                self = .null
                return
            }
            if let value = try? container.decode(Bool.self) {
                self.init(value)
                return
            }
            if let value = try? container.decode(Int.self) {
                self.init(value)
                return
            }
            if let value = try? container.decode(Double.self) {
                self.init(value)
                return
            }
            if let value = try? container.decode(String.self) {
                self.init(value)
                return
            }
        }

        if var array = try? decoder.unkeyedContainer() {
            var values: Array = []
            while !array.isAtEnd {
                values.append(try array.decode(JSON.self))
            }
            self.init(values)
            return
        }

        let object = try decoder.container(keyedBy: AnyCodingKey.self)
        var values: Object = [:]
        for key in object.allKeys {
            values[key.stringValue] = try object.decode(JSON.self, forKey: key)
        }
        self.init(values)
    }

    func encode(to encoder: Encoder) throws {
        switch rawValue {
        case is Null:
            var container = encoder.singleValueContainer()
            try container.encodeNil()
        case let value as Bool:
            var container = encoder.singleValueContainer()
            try container.encode(value)
        case let value as Int:
            var container = encoder.singleValueContainer()
            try container.encode(value)
        case let value as Double:
            var container = encoder.singleValueContainer()
            try container.encode(value)
        case let value as String:
            var container = encoder.singleValueContainer()
            try container.encode(value)
        case let values as Array:
            var container = encoder.unkeyedContainer()
            for value in values {
                try container.encode(value)
            }
        case let values as Object:
            var container = encoder.container(keyedBy: AnyCodingKey.self)
            for (key, value) in values.sortedEntries {
                try container.encode(value, forKey: AnyCodingKey(key))
            }
        default:
            try rawValue.encode(to: encoder)
        }
    }
}

private extension JSON {
    static func foundationValue(_ value: JSONValue) -> Any {
        switch value {
        case is Null:
            return NSNull()
        case let value as Bool:
            return value
        case let value as Int:
            return value
        case let value as Double:
            return value
        case let value as String:
            return value
        case let values as Array:
            return values.map(\.any)
        case let values as Object:
            return values.mapValues(\.any)
        case let value as NSNumber:
            return foundationValue(number(value).rawValue)
        default:
            return value
        }
    }

    static func unwrapped(_ value: Any?) -> Any? {
        (value as? _AnyOptional)?.jsonFlattened ?? value
    }

    static func integer(_ value: Int64) -> JSON {
        if let value = Int(exactly: value) {
            return JSON(value)
        }
        return JSON(Double(value))
    }

    static func unsignedInteger(_ value: some BinaryInteger) -> JSON {
        if let value = Int(exactly: value) {
            return JSON(value)
        }
        return JSON(Double(value))
    }

    static func number(_ value: NSNumber) -> JSON {
        if CFGetTypeID(value) == CFBooleanGetTypeID() {
            return JSON(value.boolValue)
        }
        let double = value.doubleValue
        if double.rounded() == double, let int = Int(exactly: value.int64Value) {
            return JSON(int)
        }
        return JSON(double)
    }
}

private protocol _AnyOptional {
    var jsonFlattened: Any? { get }
}

extension Optional: _AnyOptional {
    var jsonFlattened: Any? {
        flatMap { value in
            (value as? _AnyOptional)?.jsonFlattened ?? value
        }
    }
}

private struct AnyCodingKey: CodingKey {
    let stringValue: String
    let intValue: Int?

    init(_ stringValue: String) {
        self.stringValue = stringValue
        self.intValue = nil
    }

    init?(stringValue: String) {
        self.init(stringValue)
    }

    init?(intValue: Int) {
        self.stringValue = String(intValue)
        self.intValue = intValue
    }
}
