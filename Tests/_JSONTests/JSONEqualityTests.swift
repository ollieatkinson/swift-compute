import Foundation
import _JSON
import Testing

@Suite struct JSONEqualityTests {
    private struct Atom: Codable, Hashable, Sendable { let name: String }
    private struct OtherAtom: Codable, Hashable, Sendable { let name: String }
    private struct Collision: Codable, Hashable, Sendable {
        let value: Int
        func hash(into hasher: inout Hasher) { hasher.combine(0) }
    }

    @Test
    func equality_keeps_literal_kinds_and_native_values_distinct() {
        let values: [JSON] = [.null, false, true, 0, 1, .double(0), .double(1),
            "0", "1", [], [:], [1, 2], [2, 1], ["value": 1], ["value": 2],
            JSON(Date(timeIntervalSince1970: 1)), JSON(Date(timeIntervalSince1970: 2)),
            JSON(Atom(name: "coffee")), JSON(OtherAtom(name: "coffee")),
            JSON(JSONError("Missing", path: ["coffee"])),
            JSON(JSONError("Missing", path: ["bag"]))]
        for first in values.indices {
            for second in values.indices {
                #expect(values[first].isEqual(to: values[second]) == (first == second))
                #expect((values[first] == values[second]) == (first == second))
            }
        }
        #expect(JSON(Atom(name: "coffee")) == JSON(Atom(name: "coffee")))
        #expect(JSON.double(.nan) != JSON.double(.nan))
        #expect(JSON.double(-0.0) == JSON.double(0.0))
        #expect(JSON.double(-0.0).hashValue == JSON.double(0.0).hashValue)
    }

    @Test
    func object_keys_ignore_insertion_order_and_capacity_while_arrays_keep_order() {
        let entries: [(String, JSON)] = (0..<64).map { index in
            ("coffee-\(index)", ["name": .string("Coffee \(index)"),
                "native": JSON(Atom(name: "\(index)")), "rating": .int(index % 5)])
        }
        let original = JSON.object(Dictionary(uniqueKeysWithValues: entries))
        for offset in [0, 1, 7, 31, 63] {
            var object: JSON.Object = [:]
            object.reserveCapacity(entries.count + offset * 4)
            for (key, value) in entries.dropFirst(offset) + entries.prefix(offset) {
                object[key] = value
            }
            let reordered = JSON.object(object)
            #expect(original == reordered)
            #expect(original.hashValue == reordered.hashValue)
            #expect(Set([original]).contains(reordered))
            #expect([original: "found"][reordered] == "found")
        }
        #expect(JSON.array(entries.map(\.1)) != JSON.array(entries.reversed().map(\.1)))
        #expect(JSON([Int]()) == JSON.array([]))
        #expect(JSON([String: Int]()) == JSON.object([:]))
    }

    @Test
    func colliding_native_values_remain_separate_dictionary_keys() {
        let first: JSON = ["value": JSON(Collision(value: 1))]
        let same: JSON = ["value": JSON(Collision(value: 1))]
        let second: JSON = ["value": JSON(Collision(value: 2))]
        #expect(first == same && first.hashValue == same.hashValue)
        #expect(first != second)
        #expect(Set([first, same, second]).count == 2)
        let lookup = [first: "first", second: "second"]
        #expect(lookup[same] == "first")
        #expect(lookup[second] == "second")
    }
}
