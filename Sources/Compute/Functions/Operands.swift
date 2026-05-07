protocol OperandPair: Sendable {
    var lhs: JSON { get }
    var rhs: JSON { get }

    init(lhs: JSON, rhs: JSON)
}

public struct Operands: Codable, Equatable, Sendable, OperandPair {
    public let lhs: JSON
    public let rhs: JSON

    public init(lhs: JSON, rhs: JSON) {
        self.lhs = lhs
        self.rhs = rhs
    }
}
extension OperandPair {
    func computed(in frame: ComputeFrame) async throws -> Operands {
        let lhs = try await lhs.compute(frame: frame["lhs"])
        let rhs = try await rhs.compute(frame: frame["rhs"])
        return Operands(lhs: lhs, rhs: rhs)
    }

    func orderedComparison(
        string: (String, String) -> Bool,
        number: (Double, Double) -> Bool
    ) throws -> JSON {
        if case .string = lhs, case .string = rhs {
            return .bool(try string(lhs.decode(String.self), rhs.decode(String.self)))
        }
        return .bool(try number(lhs.decode(Double.self), rhs.decode(Double.self)))
    }
}
