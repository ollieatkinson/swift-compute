public struct Yes: Codable, Equatable, Sendable {
    public let `if`: JSON?
    public let unless: JSON?

    public init(if conditions: JSON? = nil, unless exceptions: JSON? = nil) {
        self.if = conditions
        self.unless = exceptions
    }
}

extension Yes: ComputeKeyword {
    public static let keyword = "yes"

    public func compute() throws -> JSON {
        let conditions = `if`?.conditionList ?? []
        let exceptions = unless?.conditionList ?? []
        let satisfied = try conditions.allSatisfy { try $0.decode(Bool.self) }
        let blocked = try exceptions.contains { try $0.decode(Bool.self) }
        return .bool(satisfied && !blocked)
    }
}
