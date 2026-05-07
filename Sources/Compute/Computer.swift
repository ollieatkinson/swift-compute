public struct Computer: Sendable {
    public let functions: [String: any AnyReturnsKeyword]

    public static let `default` = Computer([
        Compute.Keywords.This.function,
        Compute.Keywords.Yes.function,
        Compute.Keywords.Contains.function,
        Compute.Keywords.Membership.function,
        Compute.Keywords.ApproximatelyEqual.function,
        Compute.Keywords.Comparison.function,
        Compute.Keywords.Not.function,
        Compute.Keywords.Either.function,
        Compute.Keywords.Explain.function,
        Compute.Keywords.Error.function,
        Compute.Keywords.HTTP.Function(),
        Compute.Keywords.Text.function,
        Compute.Keywords.Item.function,
        Compute.Keywords.Count.function,
        Compute.Keywords.Exists.function,
        Compute.Keywords.Map.function,
        Compute.Keywords.ArraySort.function,
        Compute.Keywords.ArraySlice.function,
        Compute.Keywords.ArraySubscript.function,
        Compute.Keywords.ArrayZip.function,
        Compute.Keywords.ArrayGroup.function,
        Compute.Keywords.ArrayMap.function,
        Compute.Keywords.ArrayFilter.function,
        Compute.Keywords.ArrayReduce.function,
    ])

    public init(_ functions: [any AnyReturnsKeyword] = []) {
        self.functions = Dictionary(functions.map { ($0.name, $0) }, uniquingKeysWith: { _, last in last })
    }

    public subscript(keyword: String) -> Keyword? {
        functions[keyword].map { Keyword(name: keyword, function: $0) }
    }

    public func merging(_ functions: [any AnyReturnsKeyword]) -> Computer {
        Computer(Array(self.functions.values) + functions)
    }
}

extension Computer {
    public struct Keyword: Sendable {
        public let name: String
        public let function: any AnyReturnsKeyword

        public var isComputeKeyword: Bool {
            !(function is any ReturnsKeyword)
        }

        public var isReturnsKeyword: Bool {
            function is any ReturnsKeyword
        }
    }
}

extension Computer.Keyword: Equatable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.name == rhs.name
    }
}

extension Computer.Keyword {
    public init?(returns data: [String: JSON]?, computer: Computer = .default) {
        guard case .object(let returns)? = data?["{returns}"] else { return nil }
        guard returns.count == 1, let name = returns.keys.first else { return nil }
        guard let keyword = computer[name] else { return nil }
        self = keyword
    }
}

extension Compute {
    struct Invocation: Sendable, Equatable {
        let keyword: String
        let argument: JSON
        let fallback: JSON?

        init?(object: [String: JSON]) {
            guard case .object(let returns)? = object["{returns}"] else { return nil }
            guard returns.count == 1, let keyword = returns.keys.first, let argument = returns[keyword] else {
                return nil
            }
            self.keyword = keyword
            self.argument = argument
            self.fallback = object["default"]
        }

        var returnsJSON: JSON {
            .object([keyword: argument])
        }
    }
}
