import _JSON

extension Compute.Keyword {
    /// Tests the representation of an evaluated value without Codable conversion.
    public struct Is: Codable, Equatable, Sendable {
        public enum Kind: String, Codable, Sendable {
            case array, boolean, null, number, object, string
        }

        @Computed public var value: JSON
        public let type: Kind
    }
}

extension Compute.Keyword.Is: Compute.KeywordDefinition {
    public static let name = "is"

    public func compute(in frame: Compute.Frame) async throws -> JSON? {
        let value = try await $value.compute(in: frame)
        switch type {
        case .array: return .bool(value.array != nil)
        case .boolean: return .bool(Swift.type(of: value.rawValue) == Bool.self)
        case .null: return .bool(value.isNull)
        case .number:
            return .bool(value.rawValue is any BinaryInteger || value.rawValue is any BinaryFloatingPoint)
        case .object: return .bool(value.object != nil)
        case .string: return .bool(value.string != nil)
        }
    }
}
