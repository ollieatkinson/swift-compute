public struct Computer: Sendable {
    public let functions: [String: any AnyReturnsKeyword]

    public static let `default` = Computer([
        Keyword.This.function,
        Keyword.Yes.function,
        Keyword.Contains.function,
        Keyword.Membership.function,
        Keyword.ApproximatelyEqual.function,
        Keyword.Comparison.function,
        Keyword.Not.function,
        Keyword.Either.function,
        Keyword.Explain.function,
        Keyword.Error.function,
        Keyword.HTTP.Function(),
        Keyword.Text.function,
        Keyword.Item.function,
        Keyword.Count.function,
        Keyword.Exists.function,
        Keyword.Map.function,
        Keyword.ArraySort.function,
        Keyword.ArraySlice.function,
        Keyword.ArraySubscript.function,
        Keyword.ArrayZip.function,
        Keyword.ArrayGroup.function,
        Keyword.ArrayMap.function,
        Keyword.ArrayFilter.function,
        Keyword.ArrayReduce.function,
    ])

    public init(_ functions: [any AnyReturnsKeyword] = []) {
        self.functions = Dictionary(functions.map { ($0.name, $0) }, uniquingKeysWith: { _, last in last })
    }

    public subscript(keyword: String) -> Compute.Keyword? {
        functions[keyword].map { Compute.Keyword(name: keyword, function: $0) }
    }

    public func merging(_ functions: [any AnyReturnsKeyword]) -> Computer {
        Computer(Array(self.functions.values) + functions)
    }
}

extension Compute {
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

extension Compute.Keyword: Equatable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.name == rhs.name
    }
}

extension Compute.Keyword {
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
