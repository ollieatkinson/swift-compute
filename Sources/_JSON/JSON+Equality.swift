public extension JSON {
    static func == (lhs: JSON, rhs: JSON) -> Bool {
        lhs.isEqual(to: rhs)
    }

    func isEqual(to other: JSON) -> Bool {
        if let equal = rawValue._isEqual(to: other.rawValue) { return equal }

        // Foundation collection subclasses can bridge to literal containers
        // when the other value cannot cast back to that native subclass.
        switch rawValue {
        case let object as Object:
            return object.isEqual(to: other.rawValue)
        case let array as Array:
            return array.isEqual(to: other.rawValue)
        case is Null:
            return other.isNull
        default:
            return false
        }
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
            hasher.combine(object)
        default:
            hasher.combine(7)
            hasher.combine(String(reflecting: Swift.type(of: rawValue)))
            hasher.combine(AnyHashable(rawValue))
        }
    }

}

private extension Equatable {
    func _isEqual(to other: JSONValue) -> Bool? {
        guard let other = other as? Self else { return nil }
        return self == other
    }
}

public extension JSON.Array {
    func isEqual(to other: JSONValue) -> Bool {
        guard let other = other as? JSON.Array else {
            return false
        }
        guard count == other.count else {
            return false
        }
        return zip(self, other).allSatisfy { lhs, rhs in
            lhs.isEqual(to: rhs)
        }
    }
}

public extension JSON.Object {
    func isEqual(to other: JSONValue) -> Bool {
        guard let other = other as? JSON.Object else {
            return false
        }
        guard count == other.count else {
            return false
        }
        return allSatisfy { key, value in
            other[key].map { value.isEqual(to: $0) } ?? false
        }
    }
}
