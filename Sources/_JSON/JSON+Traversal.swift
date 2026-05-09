public extension JSON {
    struct DepthFirstTraversal: Sequence, IteratorProtocol {
        public typealias Element = (path: JSONPath, value: JSON)

        private var stack: [Element]

        public init(startingAt node: JSON) {
            self.stack = [([], node)]
        }

        public mutating func next() -> Element? {
            guard let (path, current) = stack.popLast() else {
                return nil
            }

            if let object = current.object {
                for (key, value) in object.sortedEntries.reversed() {
                    stack.append((path + [.key(key)], value))
                }
            } else if let array = current.array {
                for (index, value) in array.enumerated().reversed() {
                    stack.append((path + [.index(index)], value))
                }
            }

            return (path, current)
        }

        public func makeIterator() -> DepthFirstTraversal {
            self
        }
    }

    var depthFirstTraversal: DepthFirstTraversal {
        DepthFirstTraversal(startingAt: self)
    }
}
