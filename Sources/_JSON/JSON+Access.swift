public struct CastingError: Swift.Error, CustomStringConvertible, Sendable {
    public let description: String
    public let valueType: Any.Type
    public let type: Any.Type

    public init<Value>(value: Any?, to type: Value.Type) {
        self.valueType = Swift.type(of: value)
        self.type = type
        self.description = "\(CastingError.self)(from: \(Swift.type(of: value)), to: \(Value.self), value: \(value as Any))"
    }
}

private extension JSON {
    func cast<Value>(to type: Value.Type = Value.self) throws -> Value {
        if Value.self == JSON.self {
            return self as! Value
        }
        guard let value = rawValue as? Value else {
            throw CastingError(value: self, to: Value.self)
        }
        return value
    }
}

public extension JSON {
    func value<Path>(at path: Path) -> JSON? where Path: Collection, Path.Element == CodingIndex {
        var current = self
        for component in path {
            switch component {
            case .key(let key):
                guard let object = current.object, let value = object[key] else {
                    return nil
                }
                current = value
            case .index(let index):
                guard let array = current.array, let index = array.resolvedIndex(index) else {
                    return nil
                }
                current = array[index]
            }
        }
        return current
    }

    subscript(_ path: CodingIndex...) -> JSON {
        get {
            self[path]
        }
        set {
            self[path] = newValue
        }
    }

    subscript<Path>(_ path: Path) -> JSON where Path: Collection, Path.Element == CodingIndex {
        get {
            var current = self
            for component in path {
                current = current[component]
            }
            return current
        }
        set {
            guard let head = path.first else {
                self = newValue
                return
            }
            var child = self[head]
            child[path.dropFirst()] = newValue
            self[head] = child
        }
    }

    subscript<Value>(_ path: CodingIndex..., as type: Value.Type = Value.self) -> Value {
        get throws {
            try self[path].cast(to: Value.self)
        }
    }

    subscript<Value, Path>(
        _ path: Path,
        as type: Value.Type = Value.self
    ) -> Value where Path: Collection, Path.Element == CodingIndex {
        get throws {
            try self[path].cast(to: Value.self)
        }
    }

    subscript(component: CodingIndex) -> JSON {
        get {
            switch component {
            case .key(let key):
                return self[key]
            case .index(let index):
                return self[index]
            }
        }
        set {
            switch component {
            case .key(let key):
                self[key] = newValue
            case .index(let index):
                self[index] = newValue
            }
        }
    }

    subscript(key: String) -> JSON {
        get {
            guard let object else {
                return .null
            }
            return object[key] ?? .null
        }
        set {
            var object = object ?? [:]
            object[key] = newValue
            self = JSON(object)
        }
    }

    subscript(index: Int) -> JSON {
        get {
            guard let array, let index = array.resolvedIndex(index) else {
                return .null
            }
            return array[index]
        }
        set {
            var array = array ?? []
            let resolvedIndex: Int
            if index < 0 {
                guard let index = array.resolvedIndex(index) else {
                    return
                }
                resolvedIndex = index
            } else {
                if index >= array.endIndex {
                    array.append(contentsOf: repeatElement(.null, count: index - array.endIndex + 1))
                }
                resolvedIndex = index
            }
            array[resolvedIndex] = newValue
            self = JSON(array)
        }
    }
}

package extension Array where Element == JSON {
    func resolvedIndex(_ index: Int) -> Int? {
        if indices.contains(index) {
            return index
        }
        guard index < 0, !isEmpty else {
            return nil
        }
        let resolved = count + index
        guard indices.contains(resolved) else {
            return nil
        }
        return resolved
    }
}
