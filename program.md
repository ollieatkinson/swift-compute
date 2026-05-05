# autoresearch for swift-compute

This file adapts the loop from `~/src/github.com/karpathy/autoresearch` to this Swift package.

## Goal

Improve `Compute` runtime performance while preserving behavior. The benchmark score is lower-is-better:

```sh
swift package benchmark --target ComputeBenchmarks --metric wallClock --metric throughput --no-progress --time-units microseconds
```

The benchmark run is powered by `ordo-one/package-benchmark`. It prints percentile tables for each scenario:

```text
array_filter_512
│ Time (wall clock) (μs) *  │ ... │ p50 │ ...
```

For experiment tracking, record `score_us` as the geometric mean of the `p50` wall-clock microsecond values for:

- `reference_fanout`
- `array_filter_512`
- `array_map_512`
- `reactive_updates`

## Validation

Every kept change must pass:

```sh
swift test
swift package benchmark --target ComputeBenchmarks --metric wallClock --metric throughput --no-progress --time-units microseconds
```

The benchmark executable also validates scenario outputs before timing them. A correctness failure should crash the run and the experiment must be discarded.

## Experiment Loop

1. Read the current score from `swift package benchmark --target ComputeBenchmarks --metric wallClock --metric throughput --no-progress --time-units microseconds`.
2. Make one focused performance change.
3. Run `swift test` if the change is behaviorally risky.
4. Run the benchmark command.
5. Record the result in `results.tsv` using tab-separated columns:

```text
commit	score_us	status	description
```

Use `workspace` for the commit column when experimenting without commits.

6. Keep the change only if the full benchmark improves and tests pass. Otherwise revert the experiment.

Prefer small, explainable changes. Do not optimize by weakening benchmark coverage or changing expected results.
