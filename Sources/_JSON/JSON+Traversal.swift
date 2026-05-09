public extension JSON {
    struct DepthFirstTraversal: Sequence, IteratorProtocol {
        public typealias Element = (path: JSONPath, value: JSON)

        private var buffer: [Element]

        public init(startingAt node: JSON) {
            self.buffer = [([], node)]
        }

        public mutating func next() -> Element? {
            guard !buffer.isEmpty else {
                return nil
            }
            let (path, current) = buffer.removeFirst()

            if let object = current.object {
                for (key, value) in object.sortedEntries.reversed() {
                    buffer.insert((path + [.key(key)], value), at: 0)
                }
            } else if let array = current.array {
                for (index, value) in array.enumerated().reversed() {
                    buffer.insert((path + [.index(index)], value), at: 0)
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

    struct BreadthFirstTraversal: Sequence, IteratorProtocol {
        public typealias Element = (path: JSONPath, value: JSON)

        private var buffer: [Element]

        public init(startingAt node: JSON) {
            self.buffer = [([], node)]
        }

        public mutating func next() -> Element? {
            guard !buffer.isEmpty else {
                return nil
            }
            let (path, current) = buffer.removeFirst()

            if let object = current.object {
                for (key, value) in object.sortedEntries {
                    buffer.append((path + [.key(key)], value))
                }
            } else if let array = current.array {
                for (index, value) in array.enumerated() {
                    buffer.append((path + [.index(index)], value))
                }
            }

            return (path, current)
        }

        public func makeIterator() -> BreadthFirstTraversal {
            self
        }
    }

    var breadthFirstTraversal: BreadthFirstTraversal {
        BreadthFirstTraversal(startingAt: self)
    }
}
