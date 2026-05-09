import _JSON

extension Compute {
    struct Invocation: Sendable, Equatable {
        let keyword: String
        let argument: JSON
        let fallback: JSON?

        init?(object: [String: JSON]) {
            guard let returns = object["{returns}"]?.object else { return nil }
            guard returns.count == 1, let keyword = returns.keys.first, let argument = returns[keyword] else {
                return nil
            }
            self.keyword = keyword
            self.argument = argument
            self.fallback = object["default"]
        }

        var json: JSON {
            .object([keyword: argument])
        }
    }
}
