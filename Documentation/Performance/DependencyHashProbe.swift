// Standalone Release key-lifetime diagnostic. Build the package tests first
// so @testable access to the unchanged internal key initializer is available.
// DEPENDENCY_HASH_REPORT_PATH selects the report; no native UI is mounted.
@testable import Compute
import Foundation

#if REQUEST_KEYS
typealias ProbeKey = Compute.RequestKey
#else
typealias ProbeKey = Compute.Dependency
#endif

@main struct DependencyHashProbe {
    static func main() throws {
        let payload: JSON = .object(Dictionary(uniqueKeysWithValues: (0..<128).map { index in
            (String(index), ["value": .int(index), "label": .string(String(repeating: "Coffee ", count: 16))])
        }))
        var samples: [Double] = []
        var checksum = 0
        for sample in 0..<11 {
            let start = ContinuousClock.now
            let keys = (0..<16).map { index in
                ProbeKey(keyword: "source", data: ["id": .int(index), "context": payload], depth: index % 3)
            }
            var values = Dictionary(uniqueKeysWithValues: keys.map { ($0, 0) })
            let membership = Set(keys)
            for index in 0..<512 {
                let key = keys[index % keys.count]
                precondition(membership.contains(key))
                values[key, default: 0] += 1
            }
            let elapsed = start.duration(to: .now).components
            if sample >= 2 {
                samples.append(Double(elapsed.seconds) * 1e9 + Double(elapsed.attoseconds) / 1e9)
            }
            precondition(values.values.allSatisfy { $0 == 32 })
            checksum += values.values.reduce(0, +)
        }
        let counter = HashCount()
        let data = JSON(CountedRequest(id: 1, count: counter))
        let first = ProbeKey(keyword: "source", data: data, depth: 0)
        let second = ProbeKey(keyword: "source", data: data, depth: 0)
        let values = [first: "shared"]
        for _ in 0..<100 { precondition(values[second] == "shared") }
        let report: JSON = [
            "scope": "16 complete keys, shared 128-entry request context, construction/insertion/set-membership/512 dictionary increments; two warmups, nine samples. Separate native-leaf hash-call diagnostic includes key construction and 100 equal-key lookups. No UI or frame timing.",
            "samples_ns": .array(samples.map(JSON.double)),
            "checksum": .int(checksum), "native_hash_calls": .int(counter.value),
            "public_dependency_inline_bytes": .int(MemoryLayout<Compute.Dependency>.size),
            "runtime_key_inline_bytes": .int(MemoryLayout<ProbeKey>.size),
            "thermal_state": .int(ProcessInfo.processInfo.thermalState.rawValue)
        ]
        if let path = ProcessInfo.processInfo.environment["DEPENDENCY_HASH_REPORT_PATH"] {
            try report.data(options: [.prettyPrinted, .sortedKeys]).write(to: URL(fileURLWithPath: path))
        }
    }
}

private final class HashCount: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    var value: Int { lock.withLock { count } }
    func increment() { lock.withLock { count += 1 } }
}

private struct CountedRequest: Hashable, Sendable, Codable {
    let id: Int
    let count: HashCount
    init(id: Int, count: HashCount) { self.id = id; self.count = count }
    init(from decoder: any Decoder) throws {
        id = try decoder.singleValueContainer().decode(Int.self)
        count = HashCount()
    }
    func encode(to encoder: any Encoder) throws {
        var value = encoder.singleValueContainer()
        try value.encode(id)
    }
    static func == (lhs: Self, rhs: Self) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { count.increment(); hasher.combine(id) }
}
