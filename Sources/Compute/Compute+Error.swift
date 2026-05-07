import Foundation

public enum Compute {
    public enum Error: Swift.Error, Equatable, Sendable {
        case unresolvedReference(JSON)
        case recursionLimitExceeded
    }

    public struct Context: Equatable, Sendable {
        public var item: JSON?

        public init(item: JSON? = nil) {
            self.item = item
        }

        public func with(item: JSON) -> Context {
            var context = self
            context.item = item
            return context
        }
    }
}
