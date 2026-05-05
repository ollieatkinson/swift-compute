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

extension Yes: DirectComputeKeyword {
    static func computeDirectly(from input: JSON) throws -> JSON {
        guard case .object(let object) = input else {
            return try JSON.decoded(Yes.self, from: input).compute()
        }
        let conditions = object["if"]?.conditionList ?? []
        for condition in conditions where try !condition.boolValue() {
            return .bool(false)
        }
        let exceptions = object["unless"]?.conditionList ?? []
        for exception in exceptions where try exception.boolValue() {
            return .bool(false)
        }
        return .bool(true)
    }
}

private extension JSON {
    func boolValue() throws -> Bool {
        if case .bool(let value) = self {
            return value
        }
        return try decode(Bool.self)
    }
}
