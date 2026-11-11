import _JSON

public enum Compute {
    public enum Error: Swift.Error, Equatable, Sendable {
        case unresolvedReference(JSON)
        case recursionLimitExceeded
    }

    public struct Context: Equatable, Sendable {
        public var item: JSON?
        var referenceContext: [String: JSON]?

        public init(item: JSON? = nil, scope: [String: JSON]? = nil) {
            self.item = item
            self.referenceContext = scope
        }

        public func with(item: JSON) -> Context {
            var context = self
            context.item = item
            return context
        }
    }
}
