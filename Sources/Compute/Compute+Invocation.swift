import _JSON

extension Compute {
    struct Invocation: Sendable, Equatable {
        let keyword: String
        let data: JSON
        let fallback: JSON?

        init?(object: [String: JSON]) {
            guard let returns = object["{returns}"]?.object else { return nil }
            guard returns.count == 1, let keyword = returns.keys.first, let data = returns[keyword] else {
                return nil
            }
            self.keyword = keyword
            self.data = data
            self.fallback = object["default"]
        }

        var json: JSON {
            .object([keyword: data])
        }
    }
}
