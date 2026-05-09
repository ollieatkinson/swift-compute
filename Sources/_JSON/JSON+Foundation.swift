import AnyCoding
import Foundation

public extension JSON {
    init(jsonObject value: Any?) throws {
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

    init(data: Data, options: JSONSerialization.ReadingOptions = [.fragmentsAllowed]) throws {
        try self.init(jsonObject: JSONSerialization.jsonObject(with: data, options: options))
    }

    var any: Any {
        Self.foundationValue(rawValue)
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

extension JSON {
    static func unwrapped(_ value: Any?) -> Any? {
        (value as? _AnyOptional)?.jsonFlattened ?? value
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
