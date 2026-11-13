@testable import Compute
import Foundation
import Testing

@Suite struct DependencyTests {
    @Test func native_input_can_change_before_dependencies_enter_a_collection() {
        let value = MutableRequest(1)
        let first = Compute.Dependency(keyword: "source", data: JSON(value), depth: 0)
        // No key has entered a hashed collection. Native JSON values retain
        // their own semantics; a let JSON field does not freeze its payload.
        value.set(2)
        let second = Compute.Dependency(keyword: "source", data: JSON(value), depth: 0)
        #expect(first == second)
        #expect(first.hashValue == second.hashValue)
        #expect(Set([first, second]).count == 1)
        #expect(Set([Compute.RequestKey(first), Compute.RequestKey(second)]).count == 1)
    }

    @Test func request_identity_includes_keyword_depth_and_complete_input() {
        let base = Compute.Dependency(keyword: "source", data: ["id": "coffee", "owner": "one"], depth: 0)
        let same = Compute.Dependency(keyword: "source", data: ["owner": "one", "id": "coffee"], depth: 0)
        let others = [
            Compute.Dependency(keyword: "other", data: base.data, depth: 0),
            Compute.Dependency(keyword: "source", data: base.data, depth: 1),
            Compute.Dependency(keyword: "source", data: ["id": "coffee", "owner": "two"], depth: 0),
            Compute.Dependency(keyword: "source", data: ["id": "coffee", "owner": .null], depth: 0),
            Compute.Dependency(keyword: "source", data: ["id": "coffee"], depth: 0),
        ]
        #expect(base == same)
        #expect([base: "shared"][same] == "shared")
        #expect(Set([base, same] + others).count == 6)
        #expect(Set(([base, same] + others).map(Compute.RequestKey.init)).count == 6)
        for other in others { #expect(other != base) }
    }

    @Test func native_values_and_bridged_empty_containers_keep_request_sharing() {
        let native = Compute.Dependency(keyword: "source", data: [
            "date": JSON(Date(timeIntervalSince1970: 42)),
            "rows": JSON([Int]()), "fields": JSON([String: Int]()),
        ], depth: 4)
        let literal = Compute.Dependency(keyword: "source", data: [
            "fields": .object([:]), "rows": .array([]),
            "date": JSON(Date(timeIntervalSince1970: 42)),
        ], depth: 4)
        #expect(native == literal && literal == native)
        #expect(Set([native, literal]).count == 1)
        #expect([native: "shared"][literal] == "shared")
        #expect([literal: "shared"][native] == "shared")
        #expect([Compute.RequestKey(native): "shared"][Compute.RequestKey(literal)] == "shared")
    }

    @Test func colliding_native_requests_and_later_input_edits_remain_distinct() {
        var input: JSON.Object = ["key": JSON(CollidingRequest(id: 1))]
        let first = Compute.Dependency(keyword: "source", data: .object(input), depth: 0)
        input["key"] = JSON(CollidingRequest(id: 2))
        let second = Compute.Dependency(keyword: "source", data: .object(input), depth: 0)
        let copy = first
        let values = [first: "one", second: "two"]
        #expect(first != second)
        #expect(first.hashValue == second.hashValue)
        #expect(values[first] == "one" && values[second] == "two")
        #expect(values[copy] == "one")
        #expect([Compute.RequestKey(first): "one", Compute.RequestKey(second): "two"].count == 2)
        #expect(values[Compute.Dependency(keyword: "source", data: ["key": JSON(CollidingRequest(id: 1))], depth: 0)] == "one")
    }
}

private struct CollidingRequest: Hashable, Sendable, Codable {
    let id: Int
    func hash(into hasher: inout Hasher) { hasher.combine(0) }
}

private final class MutableRequest: Hashable, @unchecked Sendable, Codable {
    private let lock = NSLock()
    private var storage: Int
    private var value: Int { lock.withLock { storage } }
    init(_ value: Int) { storage = value }
    func set(_ value: Int) { lock.withLock { storage = value } }
    static func == (lhs: MutableRequest, rhs: MutableRequest) -> Bool { lhs.value == rhs.value }
    func hash(into hasher: inout Hasher) { hasher.combine(value) }
    init(from decoder: any Decoder) throws { storage = try decoder.singleValueContainer().decode(Int.self) }
    func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(value)
    }
}
