import _JSON

extension Compute {
    /// An immutable result and the completed work captured with that result.
    /// Kept in the source's graph signal, never read from later runtime thoughts.
    struct Outcome: Equatable, Sendable {
        let result: Result<JSON, JSONError>
        var thoughts: [Thought] = []
    }
}
