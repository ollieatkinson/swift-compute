import Compute
import Testing

@Suite(.serialized)
struct TypedJSONBehaviorTests {

    @Test func json_supports_swift_literal_syntax() throws {
        let value: JSON = [
            "address": [
                "city": "London",
                "postcode": "E1",
            ],
            "age": 32,
            "enabled": true,
            "missing": nil,
            "name": "Oliver",
            "scores": [1, 2, 3],
            "weight": 80.5,
        ]

        #expect(value == .object([
            "address": .object([
                "city": .string("London"),
                "postcode": .string("E1"),
            ]),
            "age": .int(32),
            "enabled": .bool(true),
            "missing": .null,
            "name": .string("Oliver"),
            "scores": .array([.int(1), .int(2), .int(3)]),
            "weight": .double(80.5),
        ]))
    }

    @Test func json_equality_is_structural_and_typed() throws {
        let integer: JSON = 1
        let double: JSON = 1.0
        let integerDocument: JSON = ["values": [1], "count": 1]
        let doubleDocument: JSON = ["values": [1.0], "count": 1.0]

        #expect(integer != double)
        #expect(integerDocument != doubleDocument)
    }

    @Test func literal_json_values_can_decode_to_concrete_models() async throws {
        try await expect(users[0], as: User.self, equals: User(
            name: "Milos",
            age: 32,
            weight: 78.2,
            isClearToFly: true,
            address: Address(city: "Belgrade", postcode: "11000")
        ))
    }

    @Test func computed_json_values_can_decode_to_concrete_types() async throws {
        try await expect(
            ["{returns}": ["item": ["address", "city"]]],
            as: String.self,
            in: Compute.Context(item: users[1]),
            equals: "London"
        )
        try await expect(
            [
                "{returns}": [
                    "comparison": [
                        "greater_or_equal": [
                            "lhs": ["{returns}": ["item": ["age"]]],
                            "rhs": 18,
                        ],
                    ],
                ],
            ],
            as: Bool.self,
            in: Compute.Context(item: users[2]),
            equals: true
        )
    }

    @Test func json_decoder_preserves_primitive_types() throws {
        struct Decoded: Decodable, Equatable {
            let count: Int
            let ratio: Double
            let enabled: Bool
            let title: String
        }

        let value: JSON = [
            "count": 1,
            "enabled": true,
            "ratio": 2,
            "title": "feature",
        ]

        #expect(try JSON.int(1).decode(JSON.self) == .int(1))
        #expect(try value.decode(Decoded.self) == Decoded(count: 1, ratio: 2, enabled: true, title: "feature"))
    }

    @Test func json_any_round_trips_through_foundation_values() throws {
        let value: JSON = [
            "enabled": true,
            "missing": nil,
            "nested": ["count": 1],
            "scores": [1, 2, 3],
            "title": "17.1",
        ]

        #expect(JSON(value.any) == value)
        #expect(JSON.returns("item", []) == ["{returns}": ["item": []]])
    }
}
