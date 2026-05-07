import Compute
import Testing

@Suite(.serialized)
struct ArrayReduceTests {
    @Test func foldsValuesUsingAccumulatorItemAndIndexContext() async throws {
        let json: JSON = [
            "{returns}": [
                "array_reduce": [
                    "array": [1, 2, 3, 4],
                    "initial": 0,
                    "next": [
                        "{returns}": [
                            "add": [
                                "lhs": ["{returns}": ["item": ["accumulator"]]],
                                "rhs": ["{returns}": ["item": ["item"]]],
                            ],
                        ],
                    ],
                ],
            ],
        ]

        #expect(try await value(json, functions: [add]) == 10)
    }

    @Test func exposesTheCurrentIndexInTheReductionContext() async throws {
        let json: JSON = [
            "{returns}": [
                "array_reduce": [
                    "array": ["a", "b", "c"],
                    "initial": 0,
                    "next": [
                        "{returns}": [
                            "add": [
                                "lhs": ["{returns}": ["item": ["accumulator"]]],
                                "rhs": ["{returns}": ["item": ["index"]]],
                            ],
                        ],
                    ],
                ],
            ],
        ]

        #expect(try await value(json, functions: [add]) == 3)
    }

    @Test func recomputesWhenAReferencedArrayChanges() async throws {
        let references = TestReferences()
        await references.set("scores", to: [1, 2])
        let json: JSON = [
            "{returns}": [
                "array_reduce": [
                    "array": ["{returns}": ["from": ["reference": "scores"]]],
                    "initial": 0,
                    "next": [
                        "{returns}": [
                            "add": [
                                "lhs": ["{returns}": ["item": ["accumulator"]]],
                                "rhs": ["{returns}": ["item": ["item"]]],
                            ],
                        ],
                    ],
                ],
            ],
        ]
        let runtime = ComputeRuntime(
            document: json,
            functions: [Keyword.From.Function(references: references), add]
        )
        var stream = runtime.run().makeAsyncIterator()

        await expectNext(&stream, equals: .success(3))
        await references.set("scores", to: [1, 2, 3])
        await expectNext(&stream, equals: .success(6))

        await references.finish()
        await runtime.cancel()
    }
}

private let add = AnyComputeFunction(name: "add") { input in
    guard case .object(let object) = input else {
        throw JSONError("add expected an object")
    }
    let lhs = try (object["lhs"] ?? .null).decode(Int.self)
    let rhs = try (object["rhs"] ?? .null).decode(Int.self)
    return .int(lhs + rhs)
}
