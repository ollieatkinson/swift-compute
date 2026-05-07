import Foundation
import AnyCoding

public enum JSON: Equatable, Hashable, Sendable {
    case null
    case bool(Bool)
    case int(Int)
    case double(Double)
    case string(String)
    case array([JSON])
    case object([String: JSON])

    public init(_ value: some Any) {
        switch value {
        case let value as JSON:
            self = value
        case is NSNull:
            self = .null
        case let value as Bool:
            self = .bool(value)
        case let value as Int:
            self = .int(value)
        case let value as Int8:
            self = .int(Int(value))
        case let value as Int16:
            self = .int(Int(value))
        case let value as Int32:
            self = .int(Int(value))
        case let value as Int64:
            if let narrowed = Int(exactly: value) {
                self = .int(narrowed)
            } else {
                self = .double(Double(value))
            }
        case let value as UInt:
            if let narrowed = Int(exactly: value) {
                self = .int(narrowed)
            } else {
                self = .double(Double(value))
            }
        case let value as UInt8:
            self = .int(Int(value))
        case let value as UInt16:
            self = .int(Int(value))
        case let value as UInt32:
            if let narrowed = Int(exactly: value) {
                self = .int(narrowed)
            } else {
                self = .double(Double(value))
            }
        case let value as UInt64:
            if let narrowed = Int(exactly: value) {
                self = .int(narrowed)
            } else {
                self = .double(Double(value))
            }
        case let value as Float:
            self = .double(Double(value))
        case let value as Double:
            self = .double(value)
        case let value as String:
            self = .string(value)
        case let value as [JSON]:
            self = .array(value)
        case let value as [String: JSON]:
            self = .object(value)
        case let values as [Any]:
            self = .array(values.map(JSON.init))
        case let values as [String: Any]:
            self = .object(values.mapValues(JSON.init))
        case let value as NSNumber:
            self = Self.number(value)
        default:
            self = .string(String(describing: value))
        }
    }

    public static func returns(_ keyword: String, _ argument: JSON, default fallback: JSON? = nil) -> JSON {
        var object: [String: JSON] = [
            "{returns}": .object([keyword: argument]),
        ]
        if let fallback {
            object["default"] = fallback
        }
        return .object(object)
    }

    static func encoded(_ value: some Encodable) throws -> JSON {
        try JSON(anyCodingValue: JSONAnyEncoder().encode(value))
    }

    static func decoded<Value: Decodable>(
        _ type: Value.Type = Value.self,
        from value: JSON
    ) throws -> Value {
        try JSONAnyDecoder().decode(Value.self, from: value.any)
    }

    public func decode<Value: Decodable>(_ type: Value.Type = Value.self) throws -> Value {
        try JSONAnyDecoder().decode(Value.self, from: any)
    }

}

extension JSON {
    public var any: Any {
        switch self {
        case .null:
            return NSNull()
        case .bool(let value):
            return value
        case .int(let value):
            return value
        case .double(let value):
            return value
        case .string(let value):
            return value
        case .array(let values):
            return values.map(\.any)
        case .object(let values):
            return values.mapValues(\.any)
        }
    }

    init(anyCodingValue value: Any?) throws {
        switch value {
        case nil:
            self = .null
        case is NSNull:
            self = .null
        case let value as JSON:
            self = value
        case let value as Bool:
            self = .bool(value)
        case let value as Int:
            self = .int(value)
        case let value as Int8:
            self = .int(Int(value))
        case let value as Int16:
            self = .int(Int(value))
        case let value as Int32:
            self = .int(Int(value))
        case let value as Int64:
            self = try Self.integer(value)
        case let value as UInt:
            self = try Self.unsignedInteger(value)
        case let value as UInt8:
            self = .int(Int(value))
        case let value as UInt16:
            self = .int(Int(value))
        case let value as UInt32:
            self = try Self.unsignedInteger(UInt(value))
        case let value as UInt64:
            self = try Self.unsignedInteger(value)
        case let value as Float:
            self = .double(Double(value))
        case let value as Double:
            self = .double(value)
        case let value as String:
            self = .string(value)
        case let value as NSNumber:
            self = Self.number(value)
        case let values as [Any]:
            self = .array(try values.map(JSON.init(anyCodingValue:)))
        case let values as [String: Any]:
            self = .object(try values.mapValues(JSON.init(anyCodingValue:)))
        default:
            throw JSONError("Unsupported encoded value \(String(describing: value))")
        }
    }

    private static func integer(_ value: Int64) throws -> JSON {
        if let value = Int(exactly: value) {
            return .int(value)
        }
        return .double(Double(value))
    }

    private static func unsignedInteger(_ value: some BinaryInteger) throws -> JSON {
        if let value = Int(exactly: value) {
            return .int(value)
        }
        return .double(Double(value))
    }

    private static func number(_ value: NSNumber) -> JSON {
        if CFGetTypeID(value) == CFBooleanGetTypeID() {
            return .bool(value.boolValue)
        }
        let double = value.doubleValue
        if double.rounded() == double, let int = Int(exactly: value.int64Value) {
            return .int(int)
        }
        return .double(double)
    }
}

private final class JSONAnyEncoder: AnyEncoder {
    override func convert(_ value: some Any) throws -> Any? {
        if let value = value as? JSON {
            return value.any
        }
        if let value = value as? Compute.Keywords.Item {
            return value.path.map(\.json.any)
        }
        if let values = value as? [Any] {
            return try values.map { try Self.anyCodingValue($0) ?? NSNull() }
        }
        if let values = value as? [String: Any] {
            return try values.mapValues { try Self.anyCodingValue($0) ?? NSNull() }
        }
        return try super.convert(value)
    }

    private static func anyCodingValue(_ value: Any) throws -> Any? {
        switch value {
        case let value as JSON:
            return value.any
        case let value as Compute.Keywords.Item:
            return value.path.map(\.json.any)
        case is NSNull:
            return NSNull()
        case let value as Bool:
            return value
        case let value as Int:
            return value
        case let value as Int8:
            return Int(value)
        case let value as Int16:
            return Int(value)
        case let value as Int32:
            return Int(value)
        case let value as Int64:
            return value
        case let value as UInt:
            return value
        case let value as UInt8:
            return Int(value)
        case let value as UInt16:
            return Int(value)
        case let value as UInt32:
            return value
        case let value as UInt64:
            return value
        case let value as Float:
            return Double(value)
        case let value as Double:
            return value
        case let value as String:
            return value
        case let value as NSNumber:
            return value
        case let values as [Any]:
            return try values.map { try anyCodingValue($0) ?? NSNull() }
        case let values as [String: Any]:
            return try values.mapValues { try anyCodingValue($0) ?? NSNull() }
        case let value as any Encodable:
            return try JSONAnyEncoder().encode(value)
        default:
            return nil
        }
    }
}

private final class JSONAnyDecoder: AnyDecoder {
    override func convert<Value>(_ any: Any, to type: Value.Type) throws -> Any? {
        if Value.self == JSON.self {
            return try JSON(anyCodingValue: any)
        }
        return try super.convert(any, to: type)
    }
}

extension JSON: ExpressibleByNilLiteral {
    public init(nilLiteral: ()) {
        self = .null
    }
}

extension JSON: ExpressibleByBooleanLiteral {
    public init(booleanLiteral value: Bool) {
        self = .bool(value)
    }
}

extension JSON: ExpressibleByIntegerLiteral {
    public init(integerLiteral value: Int) {
        self = .int(value)
    }
}

extension JSON: ExpressibleByFloatLiteral {
    public init(floatLiteral value: Double) {
        self = .double(value)
    }
}

extension JSON: ExpressibleByStringLiteral {
    public init(stringLiteral value: String) {
        self = .string(value)
    }
}

extension JSON: ExpressibleByArrayLiteral {
    public init(arrayLiteral elements: JSON...) {
        self = .array(elements)
    }
}

extension JSON: ExpressibleByDictionaryLiteral {
    public init(dictionaryLiteral elements: (String, JSON)...) {
        self = .object(Dictionary(elements, uniquingKeysWith: { _, last in last }))
    }
}

extension JSON: Codable {
    public init(from decoder: Decoder) throws {
        if let container = try? decoder.singleValueContainer() {
            if container.decodeNil() {
                self = .null
                return
            }
            if let value = try? container.decode(Bool.self) {
                self = .bool(value)
                return
            }
            if let value = try? container.decode(Int.self) {
                self = .int(value)
                return
            }
            if let value = try? container.decode(Double.self) {
                self = .double(value)
                return
            }
            if let value = try? container.decode(String.self) {
                self = .string(value)
                return
            }
        }
        if var array = try? decoder.unkeyedContainer() {
            var values: [JSON] = []
            while !array.isAtEnd {
                values.append(try array.decode(JSON.self))
            }
            self = .array(values)
            return
        }
        let object = try decoder.container(keyedBy: DynamicCodingKey.self)
        var values: [String: JSON] = [:]
        for key in object.allKeys {
            values[key.stringValue] = try object.decode(JSON.self, forKey: key)
        }
        self = .object(values)
    }

    public func encode(to encoder: Encoder) throws {
        switch self {
        case .null:
            var container = encoder.singleValueContainer()
            try container.encodeNil()
        case .bool(let value):
            var container = encoder.singleValueContainer()
            try container.encode(value)
        case .int(let value):
            var container = encoder.singleValueContainer()
            try container.encode(value)
        case .double(let value):
            var container = encoder.singleValueContainer()
            try container.encode(value)
        case .string(let value):
            var container = encoder.singleValueContainer()
            try container.encode(value)
        case .array(let values):
            var container = encoder.unkeyedContainer()
            for value in values {
                try container.encode(value)
            }
        case .object(let values):
            var container = encoder.container(keyedBy: DynamicCodingKey.self)
            for key in values.keys.sorted() {
                try container.encode(values[key], forKey: DynamicCodingKey(key))
            }
        }
    }
}

private struct DynamicCodingKey: CodingKey {
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
