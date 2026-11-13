# Runtime request hashing

The runtime repeatedly uses the same normalized request in its result,
subscription, waiter, route-dependency and Brain dictionaries/sets. Synthesized
`Dependency.hash(into:)` traverses its complete JSON data for each lookup.

Sky's binding identity is smaller: owner, property and path. Compute requests
must retain keyword, execution depth and complete normalized input: arbitrary
native values and context remain valid request identity. Narrowing that input to
current UI fixtures would change sharing semantics.

An internal `RequestKey` computes the hash once when the runtime admits the
request. Copies reuse it across those existing collections. Equality still
compares the entire dependency, including deliberate hash collisions. This adds
one machine word per key; it introduces no global cache, scheduler or lifecycle
owner and changes no depth, invalidation or cancellation policy.

`Dependency` itself remains unchanged. A rejected trial cached its hash at public
value construction: a thread-safe native payload can legitimately change before
the dependency enters any hashed collection. Caching there breaks equal-value
hash congruence. The new test preserves that counterexample. Runtime keys require
identity to stay stable while tracked, just as their previous dictionary/set keys
did; they do not freeze or restrict native JSON payloads.

## Evidence — 13 November 2026

The standalone [probe](DependencyHashProbe.swift) includes construction,
insertion, membership and 512 dictionary increments over 16 requests with a
128-entry context. Eight fresh Release processes in A/B/B/A/B/A/A/B order, each
with two warmups and nine samples, have median ranges of 25.629–26.436 ms for
`Dependency` and 0.489–1.116 ms for `RequestKey`. A separate native payload records
101 hash calls versus 2 for two equal requests and 100 lookups. Public dependency
size stays 80 bytes; internal key size is 88. All processes finish at thermal
state 0. [Raw comparison](2026-11-13-request-key-probe.json.gz).

This isolated repeated-key workload is not an application-speed result. Complete
Bloom card preparation overlaps: All 395.744–425.652 ms control versus
396.302–439.974 ms candidate. A separate four-process native retained-screen
capture, using the same authored RAVE actions and fixed observation windows,
shows worker sampled CPU of 18.279–19.089 s control versus 10.555–10.909 s
candidate. Worker JSON-hashing stacks fall from 6.555–6.862 s to 0.188–0.239 s.
These are inclusive statistical CPU weights, not per-action latency. All four
captures end at thermal state 1. Source receipts overlap, and SwiftUI graph/layout
work remains. Namespace retains full provenance and per-window evidence in its
`Documentation/Performance/RequestKeyHashing.md`.

All 297 Compute/JSON/Brain test methods pass in strict Debug and Release. New
coverage includes public native mutability before collection entry, complete
context/depth identity, native dates and bridged empty containers, collisions and
copy-preserving input edits. Namespace's strict iOS build passes. Its full macOS
consumer suite remains red; do not describe this change as clearing those gates
or completing native readiness.

The probe uses `@testable import Compute`; build package tests with Release
optimization and testing enabled before compiling the standalone source. Compile
with `-D REQUEST_KEYS` for the private runtime key, or omit that definition for
the public dependency control. Use identical compiler flags and link objects,
separate fresh processes and `DEPENDENCY_HASH_REPORT_PATH` per run. The comparison
was against Compute `29a0464`, not Namespace's older published `ac5e2aa` pin.
