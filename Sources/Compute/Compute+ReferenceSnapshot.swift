import _JSON

extension Compute {
    /// A provider snapshot whose provenance is not part of its executable JSON.
    /// Embed with JSON(snapshot); only a reference read unwraps this native value.
    /// Ordinary JSON objects, including encoded lookalikes, remain ordinary data.
    public enum ReferenceSnapshot: Codable, Hashable, Sendable {
        case value(JSON, thoughts: [Thought] = [])
        case failure(JSONError, thoughts: [Thought] = [])

        var result: Result<JSON, JSONError> {
            switch self {
            case .value(let value, _): .success(value)
            case .failure(let error, _): .failure(error)
            }
        }

        var thoughts: [Thought] {
            switch self {
            case .value(_, let thoughts), .failure(_, let thoughts): thoughts
            }
        }
    }
}
