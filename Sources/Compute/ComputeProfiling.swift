import Dispatch
import Foundation
import Synchronization

public struct ComputeProfileSnapshot: Sendable, CustomStringConvertible {
    public struct Entry: Sendable {
        public let name: String
        public let count: Int
        public let totalNanoseconds: UInt64

        public var averageNanoseconds: Double {
            guard count > 0 else { return 0 }
            return Double(totalNanoseconds) / Double(count)
        }
    }

    public let entries: [Entry]

    public var totalNanoseconds: UInt64 {
        entries.reduce(0) { $0 + $1.totalNanoseconds }
    }

    public var description: String {
        guard !entries.isEmpty else { return "No compute profile samples." }
        var lines = ["name\tcount\ttotal_us\tavg_us\tshare"]
        let total = Double(max(totalNanoseconds, 1))
        for entry in entries {
            let totalMicroseconds = Double(entry.totalNanoseconds) / 1_000
            let averageMicroseconds = entry.averageNanoseconds / 1_000
            let share = Double(entry.totalNanoseconds) / total * 100
            lines.append("\(entry.name)\t\(entry.count)\t\(format(totalMicroseconds))\t\(format(averageMicroseconds))\t\(format(share))%")
        }
        return lines.joined(separator: "\n")
    }

    private func format(_ value: Double) -> String {
        String(format: "%.3f", value)
    }
}

public enum ComputeProfiling {
    private struct State: Sendable {
        var entries: [String: Entry] = [:]
    }

    private struct Entry: Sendable {
        var count = 0
        var totalNanoseconds: UInt64 = 0
    }

    private static let enabled = Atomic(false)
    private static let state = Mutex(State())

    public static var isEnabled: Bool {
        enabled.load(ordering: .relaxed)
    }

    public static func setEnabled(_ isEnabled: Bool) {
        enabled.store(isEnabled, ordering: .relaxed)
    }

    public static func reset() {
        state.withLock { state in
            state.entries.removeAll(keepingCapacity: true)
        }
    }

    public static func snapshot() -> ComputeProfileSnapshot {
        state.withLock { state in
            let entries = state.entries.map { name, entry in
                ComputeProfileSnapshot.Entry(
                    name: name,
                    count: entry.count,
                    totalNanoseconds: entry.totalNanoseconds
                )
            }
            .sorted { lhs, rhs in
                if lhs.totalNanoseconds != rhs.totalNanoseconds {
                    return lhs.totalNanoseconds > rhs.totalNanoseconds
                }
                return lhs.name < rhs.name
            }
            return ComputeProfileSnapshot(entries: entries)
        }
    }

    static func start() -> UInt64? {
        guard isEnabled else { return nil }
        return DispatchTime.now().uptimeNanoseconds
    }

    static func record(_ name: StaticString, since start: UInt64?) {
        guard let start else { return }
        record(name, elapsedSince: start)
    }

    static func measure<Value>(
        _ name: StaticString,
        _ operation: () throws -> Value
    ) rethrows -> Value {
        guard isEnabled else {
            return try operation()
        }
        let start = DispatchTime.now().uptimeNanoseconds
        do {
            let value = try operation()
            record(name, elapsedSince: start)
            return value
        } catch {
            record(name, elapsedSince: start)
            throw error
        }
    }

    static func measure<Value>(
        _ name: StaticString,
        _ operation: () async throws -> Value
    ) async rethrows -> Value {
        guard isEnabled else {
            return try await operation()
        }
        let start = DispatchTime.now().uptimeNanoseconds
        do {
            let value = try await operation()
            record(name, elapsedSince: start)
            return value
        } catch {
            record(name, elapsedSince: start)
            throw error
        }
    }

    private static func record(_ name: StaticString, elapsedSince start: UInt64) {
        let elapsed = DispatchTime.now().uptimeNanoseconds - start
        let key = String(describing: name)
        state.withLock { state in
            state.entries[key, default: Entry()].count += 1
            state.entries[key, default: Entry()].totalNanoseconds += elapsed
        }
    }
}
