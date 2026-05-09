import Compute
import Testing

@Suite(.serialized)
struct ArrayReduceTests {
    @Test func folds_values_using_accumulator_item_and_index_context() async throws {
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

    @Test func exposes_the_current_index_in_the_reduction_context() async throws {
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

    @Test func recomputes_when_a_referenced_array_changes() async throws {
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
        let runtime = Compute.Runtime(
            document: json,
            functions: [Compute.Keyword.From.Function(references: references), add]
        )
        var stream = runtime.run().makeAsyncIterator()

        await expectNext(&stream, equals: .success(3))
        await references.set("scores", to: [1, 2, 3])
        await expectNext(&stream, equals: .success(6))

        await references.finish()
        await runtime.cancel()
    }
}

private let add = AddFunction()

private struct AddFunction: AnyReturnsKeyword {
    let name = "add"

    func compute(data input: JSON, frame: Compute.Frame) async throws -> JSON? {
        let input = try await frame.compute(input)
        guard let object = input.object else {
            throw JSONError("add expected an object")
        }
        let lhs = try (object["lhs"] ?? .null).decode(Int.self)
        let rhs = try (object["rhs"] ?? .null).decode(Int.self)
        return .int(lhs + rhs)
    }
}
