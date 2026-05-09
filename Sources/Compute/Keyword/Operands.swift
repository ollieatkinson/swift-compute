import _JSON
protocol OperandPair: Sendable {
    var lhs: JSON { get }
    var rhs: JSON { get }
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
    func orderedComparison(
        string: (String, String) -> Bool,
        number: (Double, Double) -> Bool
    ) throws -> JSON {
        if lhs.string != nil, rhs.string != nil {
            return .bool(try string(lhs.decode(String.self), rhs.decode(String.self)))
        }
        return .bool(try number(lhs.decode(Double.self), rhs.decode(Double.self)))
    }
}

func computedOperands(
    lhs: Computed<JSON>,
    rhs: Computed<JSON>,
    in frame: Compute.Frame
) async throws -> Operands {
    let lhs = try await lhs.compute(in: frame)
    let rhs = try await rhs.compute(in: frame)
    return Operands(lhs: lhs, rhs: rhs)
}
