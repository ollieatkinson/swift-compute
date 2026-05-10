import Foundation
import _JSON
import Testing

@Suite
struct _JSONTests {
    @Test func literal_values_use_constrained_storage_with_typed_access() throws {
        let value: JSON = [
            "enabled": true,
            "missing": nil,
            "users": [
                ["name": "Milos", "age": 32],
                ["name": "Oliver", "age": 36, "scores": [1, nil, 3]],
            ],
        ]

        let namePath: JSONPath = ["users", 1, "name"]
        let scorePath: JSONPath = ["users", 1, "scores", 1]

        #expect(try value[namePath, as: String.self] == "Oliver")
        #expect(value[scorePath].isNull)
        #expect(try value["enabled", as: Bool.self])
        #expect(value.count == 3)
    }

    @Test func path_subscripts_build_objects_and_arrays_without_enum_cases() throws {
        var value: JSON = nil
        let namePath: JSONPath = ["users", 0, "name"]
        let cityPath: JSONPath = ["users", 0, "address", "city"]

        value[namePath] = "Oliver"
        value[cityPath] = "London"

        #expect(try value[namePath, as: String.self] == "Oliver")
        #expect(try value[cityPath, as: String.self] == "London")
        #expect(value.object != nil)
        #expect(value["users"].array?.count == 1)
    }

    @Test func negative_indexes_read_and_write_from_the_end_of_arrays() throws {
        var value: JSON = [
            "items": ["a", "b", "c"],
        ]

        #expect(try value[["items", -1] as JSONPath, as: String.self] == "c")
        #expect(try value.value(at: ["items", -2] as JSONPath)?.decode(String.self) == "b")

        value[["items", -1] as JSONPath] = "last"
        #expect(try value[["items", 2] as JSONPath, as: String.self] == "last")

        value[["items", 5] as JSONPath] = "padded"
        #expect(value["items"].array?.count == 6)
        #expect(value[["items", 3] as JSONPath].isNull)
        #expect(try value[["items", 5] as JSONPath, as: String.self] == "padded")
        #expect(value.value(at: ["items", -7] as JSONPath) == nil)
    }

    @Test func codable_decode_uses_foundation_json_values_at_the_boundary() throws {
        struct User: Decodable, Equatable {
            let name: String
            let age: Int
        }

        let value: JSON = [
            "users": [
                ["name": "Milos", "age": 32],
                ["name": "Oliver", "age": 36],
            ],
        ]
        let userPath: JSONPath = ["users", 1]

        #expect(try value[userPath].decode(User.self) == User(name: "Oliver", age: 36))
    }

    @Test func wrapper_restores_hashable_sendable_codable_surface() throws {
        struct Box: Codable, Hashable, Sendable {
            let value: JSON
        }

        let box = Box(value: [
            "enabled": true,
            "missing": nil,
            "scores": [1, 2, 3],
        ])
        let decoded = try JSONDecoder().decode(Box.self, from: JSONEncoder().encode(box))

        #expect(decoded == box)
        #expect(Set([box]).contains(box))
    }

    @Test func serialization_round_trips_nulls_without_exposing_nsnull_to_callers() throws {
        let value: JSON = [
            "enabled": true,
            "missing": nil,
            "scores": [1, nil, 3],
        ]

        let data = try value.data(options: [.fragmentsAllowed, .sortedKeys])
        let decoded = try JSON(data: data)

        #expect(decoded["missing"].isNull)
        #expect(decoded[["scores", 1] as JSONPath].isNull)
        #expect(decoded.isEqual(to: value))
    }

    @Test func any_coding_decodes_foundation_and_wrapped_nulls_as_json_null() throws {
        let value: JSON = ["item": nil]
        let decoded = try value.decode([String: JSON].self)

        #expect(decoded["item"]?.isNull == true)
        #expect(try JSON(jsonObject: JSON.Null()).isNull)
    }

    @Test func structural_equality_is_explicit_and_keeps_ints_distinct_from_doubles() {
        #expect(JSON.int(1).isEqual(to: 1))
        #expect(!JSON.int(1).isEqual(to: 1.0))
        #expect(JSON.object(["value": 1]) == JSON.object(["value": 1]))
    }

    @Test func traversal_returns_paths_without_allocating_enum_json_nodes() throws {
        let value: JSON = [
            "users": [
                ["name": "Milos"],
                ["name": "Oliver"],
            ],
        ]

        let paths = value.depthFirstTraversal.map(\.path)

        #expect(paths.contains(["users", 0, "name"] as JSONPath))
        #expect(paths.contains(["users", 1, "name"] as JSONPath))
    }
}
