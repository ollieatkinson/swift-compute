import _JSON
public struct Computer: Sendable {
    public let functions: [String: any AnyReturnsKeyword]

    public static let `default` = Computer([
        Compute.Keyword.This.function,
        Compute.Keyword.Yes.function,
        Compute.Keyword.Contains.function,
        Compute.Keyword.ApproximatelyEqual.function,
        Compute.Keyword.Comparison.function,
        Compute.Keyword.Not.function,
        Compute.Keyword.Either.function,
        Compute.Keyword.Explain.function,
        Compute.Keyword.Error.function,
        Compute.Keyword.HTTP.Function(),
        Compute.Keyword.Text.function,
        Compute.Keyword.Item.function,
        Compute.Keyword.Count.function,
        Compute.Keyword.Exists.function,
        Compute.Keyword.Map.function,
        Compute.Keyword.ArraySort.function,
        Compute.Keyword.ArraySlice.function,
        Compute.Keyword.ArraySubscript.function,
        Compute.Keyword.ArrayZip.function,
        Compute.Keyword.ArrayGroup.function,
        Compute.Keyword.ArrayMap.function,
        Compute.Keyword.ArrayFilter.function,
        Compute.Keyword.ArrayReduce.function,
    ])

    public init(_ functions: [any AnyReturnsKeyword] = []) {
        self.functions = Dictionary(functions.map { ($0.name, $0) }, uniquingKeysWith: { _, last in last })
    }

    public subscript(keyword: String) -> RegisteredKeyword? {
        functions[keyword].map { RegisteredKeyword(name: keyword, function: $0) }
    }

    public func merging(_ functions: [any AnyReturnsKeyword]) -> Computer {
        Computer(Array(self.functions.values) + functions)
    }
}

extension Computer {
    public struct RegisteredKeyword: Sendable {
        public let name: String
        public let function: any AnyReturnsKeyword

        public var isComputeKeyword: Bool {
            !(function is any Compute.ReturnsKeywordDefinition)
        }

        public var isReturnsKeyword: Bool {
            function is any Compute.ReturnsKeywordDefinition
        }
    }
}

extension Computer.RegisteredKeyword: Equatable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.name == rhs.name
    }
}

extension Computer.RegisteredKeyword {
    public init?(returns data: [String: JSON]?, computer: Computer = .default) {
        guard let data, let invocation = Compute.Invocation(object: data) else { return nil }
        guard let keyword = computer[invocation.keyword] else { return nil }
        self = keyword
    }
}
