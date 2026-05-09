public enum CodingIndex: Sendable, Equatable, Hashable {
    case key(String)
    case index(Int)

    public var key: String? {
        guard case .key(let key) = self else { return nil }
        return key
    }

    public var index: Int? {
        guard case .index(let index) = self else { return nil }
        return index
    }
}

public typealias JSONPath = [CodingIndex]

extension CodingIndex: CodingKey {
    public var stringValue: String {
        switch self {
        case .key(let key):
            return key
        case .index(let index):
            return String(index)
        }
    }

    public init?(stringValue: String) {
        self = .key(stringValue)
    }

    public var intValue: Int? {
        index
    }

    public init?(intValue: Int) {
        self = .index(intValue)
    }
}

extension CodingIndex: Codable {
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let index = try? container.decode(Int.self) {
            self = .index(index)
            return
        }
        self = .key(try container.decode(String.self))
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .key(let key):
            try container.encode(key)
        case .index(let index):
            try container.encode(index)
        }
    }
}

extension CodingIndex: ExpressibleByStringLiteral,
    ExpressibleByExtendedGraphemeClusterLiteral,
    ExpressibleByUnicodeScalarLiteral
{
    public init(stringLiteral value: String) {
        self = .key(value)
    }

    public init(extendedGraphemeClusterLiteral value: String) {
        self = .key(value)
    }

    public init(unicodeScalarLiteral value: String) {
        self = .key(value)
    }
}

extension CodingIndex: ExpressibleByIntegerLiteral {
    public init(integerLiteral value: Int) {
        self = .index(value)
    }
}

extension CodingIndex: Comparable {
    public static func < (lhs: CodingIndex, rhs: CodingIndex) -> Bool {
        switch (lhs, rhs) {
        case (.index, .key):
            return true
        case (.key, .index):
            return false
        case let (.index(lhs), .index(rhs)):
            return lhs < rhs
        case let (.key(lhs), .key(rhs)):
            return lhs < rhs
        }
    }
}

extension CodingIndex: CustomStringConvertible, CustomDebugStringConvertible {
    public var description: String {
        stringValue
    }

    public var debugDescription: String {
        description
    }
}

public extension Sequence where Element == CodingIndex {
    func joined(separator: String = ".") -> String {
        lazy.map(\.description).joined(separator: separator)
    }
}
