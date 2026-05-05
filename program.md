# autoresearch for swift-compute

This file adapts the loop from `~/src/github.com/karpathy/autoresearch` to this Swift package.

## Goal

Improve `Compute` runtime performance while preserving behavior. The benchmark score is lower-is-better:

```sh
swift run -c release ComputeBenchmarks
```

For fast probes, use:

```sh
swift run -c release ComputeBenchmarks --quick --samples 2
```

The full run prints a summary like:

```text
---
score_us:          1234.567
total_seconds:     12.345
samples:           5
reference_fanout: median_us=...
array_filter_512: median_us=...
array_map_512: median_us=...
reactive_updates: median_us=...
```

`score_us` is the geometric mean of median microseconds per operation across the benchmark scenarios.

## Validation

Every kept change must pass:

```sh
swift test
swift run -c release ComputeBenchmarks
```

The benchmark executable also validates scenario outputs before timing them. A correctness failure should crash the run and the experiment must be discarded.

## Experiment Loop

1. Read the current score from `swift run -c release ComputeBenchmarks`.
2. Make one focused performance change.
3. Run `swift test` if the change is behaviorally risky.
4. Run `swift run -c release ComputeBenchmarks`.
5. Record the result in `results.tsv` using tab-separated columns:

```text
commit	score_us	status	description
```

Use `workspace` for the commit column when experimenting without commits.

6. Keep the change only if the full benchmark improves and tests pass. Otherwise revert the experiment.

Prefer small, explainable changes. Do not optimize by weakening benchmark coverage or changing expected results.
