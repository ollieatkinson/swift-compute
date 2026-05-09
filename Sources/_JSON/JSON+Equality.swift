public extension JSON {
    func isEqual(to other: JSON) -> Bool {
        Self.isEqual(rawValue, to: other.rawValue)
    }

    private static func isEqual(_ value: JSONValue, to other: JSONValue) -> Bool {
        if (value as any Equatable)._isSameType(as: other) {
            return (value as any Equatable)._isEqual(to: other)
        }

        switch value {
        case let object as JSON.Object:
            return object.isEqual(to: other)
        case let array as JSON.Array:
            return array.isEqual(to: other)
        case is JSON.Null:
            return other is JSON.Null
        default:
            return (value as any Equatable)._isEqual(to: other)
        }
    }
}

private extension Equatable {
    func _isEqual(to other: JSONValue) -> Bool {
        self == other as? Self
    }

    func _isSameType(as other: JSONValue) -> Bool {
        (other as? Self) != nil
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
