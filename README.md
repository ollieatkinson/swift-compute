# Compute

Compute lets a backend return computational rules to a device, without requiring the backend to perform the computation itself.

The backend owns the rules. The client owns the context. Compute evaluates those rules where the relevant state already lives.

That state might include accessibility information, interface state, private profile data, local preferences, or private cloud data that the backend should not need to see. Instead of asking the device to send everything up to the server, the server can send a compute document down to the device.

In that sense, Compute is edge computing for product logic.

## Why

Many product decisions depend on state that is local, private, or only meaningful on the client. Moving that state to a backend can be expensive, slow, fragile, or undesirable from a privacy point of view.

Compute is intended to support a different shape:

- backend services define the rules
- clients evaluate the rules
- values are addressed through shared, lexicon-style names
- private and local state stays close to where it belongs
- rule changes can ship without requiring a new app release
- product logic can become more expressive without centralising all data

## Installation

Add the package to your `Package.swift` dependencies:

```swift
.package(url: "https://github.com/ollieatkinson/swift-compute.git", branch: "main")
```

Then add `Compute` to your target dependencies:

```swift
.product(name: "Compute", package: "swift-compute")
```

## Example

```swift
import Compute

let document: JSON = [
    "{returns}": [
        "yes": [
            "if": [
                [
                    "{returns}": [
                        "comparison": [
                            "greater_or_equal": [
                                "lhs": [
                                    "{returns}": [
                                        "from": [
                                            "reference": "subject.age",
                                        ],
                                    ],
                                ],
                                "rhs": 18,
                            ],
                        ],
                    ],
                ],
                [
                    "{returns}": [
                        "from": [
                            "reference": "accessibility.voiceOver.enabled",
                        ],
                    ],
                ],
            ],
        ],
    ],
]

let runtime = Compute.Runtime(
    document: document,
    functions: [
        Compute.Keyword.From.Function(references: deviceReferences),
    ]
)

let value = try await runtime.value()

// value == true
```

The document can come from a backend. The values behind `subject.age` and `accessibility.voiceOver.enabled` can stay on the device, or in a private store that only the device can access.

## Self-Explainable Decisioning

Wrap a decision in `explain` when the caller needs both the computed value and a displayable trace. The explained `value` is the complete compute document, including its `{returns}` wrapper.

Custom keywords can add domain evidence with `await frame.record(Compute.Thought(...))`,
using the current frame's route and depth. `explain` captures it alongside the
value from that evaluation. Recorded input/output stays data: recording neither
evaluates embedded expressions nor creates a dependency.
Recorded errors are diagnostic evidence. Throw an error to fail execution;
`explain` and keyword defaults can handle that failure without the recorded
evidence failing the runtime again.
Failed explanations also include a Codable `JSONError` under `failure`, retaining
its message and path alongside the existing displayable `error` string.

```swift
let document: JSON = [
    "{returns}": [
        "explain": [
            "context": [
                "label": "Eligibility",
                "surface": "eligibility help text",
            ],
            "mode": "foundation_model",
            "value": <document_example_from_above>,
        ],
    ],
]

let runtime = Compute.Runtime(
    document: document,
    functions: [
        Compute.Keyword.From.Function(references: deviceReferences),
    ]
)

let explanation = try await runtime.value()

// explanation["ok"] == true
// explanation["value"] == true
// explanation["summary"] == "true"
// explanation["thoughts"] contains the evaluated references and comparisons.
// example device-model explanation:
// "You are seeing this because you are at least 18 and have VoiceOver enabled."
```

## Built-in Keywords

The default computer includes these `{returns}` keywords:

- context and literal values: `this`, `item`
- boolean logic and presence checks: `yes`, `not`, `either`, `exists`
- comparisons: `comparison` with `match`, `equal`, `less`, `greater`, `less_or_equal`, and `greater_or_equal`, plus `approximately_equal`
- collection and object helpers: `count`, `contains`, `get`, `map`, `array_map`, `array_filter`, `array_group`, `array_reduce`, `array_slice`, `array_sort`, `array_subscript`, and `array_zip`
- date and time helpers: `date`, `seconds`
- text and network values: `text`, `http`
- diagnostics and explanation: `error`, `explain`

`get` evaluates its `value`, then selects a literal `path` of string keys and integer indices (negative indices count from the end). An empty path returns the evaluated value. Missing paths, invalid containers and out-of-bounds indices fail; explicit nulls remain values. The selected output is not evaluated again, preserving deferred expressions returned by opaque keywords.

```swift
JSON.returns("get", [
    "value": .returns("from", ["reference": "programme.card"]),
    "path": ["title", "text"],
])
```

Reference values can be added with `Compute.Keyword.From.Function(references:)`. JavaScript evaluation can be added explicitly with `Compute.Keyword.Eval.function`.

`from` detects repeated reference requests along one resolution path and reports
their names and explicit context, for example `Reference cycle: first -> second -> first`.
References inside a returned template inherit the enclosing request's effective
context; their explicit bindings take precedence. The effective bindings also
identify live dependencies, so sibling uses of one template can read different
entities without sharing the wrong cached value.
Providers can implement `References.request(for:context:)` to normalize their own
reference format and supply its effective bindings. The default preserves the
request. Normalization runs before dependency sharing, cycle detection and nested
scope propagation; it should deterministically describe identity without fetching
the value or opening a subscription. Compute does not prescribe a reference schema.
Different request contexts, changing local items, and repeated reads in sibling branches remain independent.
Custom keywords can project independent rows with `frame.scoped(to: bindings)`.
This copies the branch's effective reference defaults while retaining its item,
route, depth and reference ancestry. `frame.scope` exposes those defaults to other
provider-backed keywords. Explicit `from` context and canonical native bindings
still win, including in returned templates. Sibling branches retain their own
bindings and live dependencies; this adds no authored keyword or reference schema.
Streaming keywords whose identity depends on branch scope should implement
`ReturnsKeywordDefinition.request(data:frame:)`. It receives evaluated input and
returns the effective request used by both execution and subscription sharing.
The default returns the input unchanged; normalization must not fetch values or
open subscriptions.
Live cycles keep their upstream observations and can recover when a source changes;
an authored `default` can also handle the diagnostic. The existing recursion limit
still bounds long returned-compute chains and arbitrary generated compute loops.

Custom keywords can be added by conforming to `Compute.KeywordDefinition` or `AnyReturnsKeyword`, declaring a `name`, and passing them into `Compute.Runtime`.

`contains` checks whether a string contains a substring, or whether an array contains a value.

`map` and `array_map` can copy paths directly, preserving missing fields and explicit `null`:

```json
{
  "{returns}": {
    "map": {
      "src": {"{returns}": {"item": []}},
      "dst": {},
      "copy": [
        {"from": ["t"], "to": ["title"], "required": true},
        {"from": ["sy"], "to": ["synopsis"]}
      ]
    }
  }
}
```

A copy uses either `from` or `value`. Missing optional paths are skipped; `required: true` fails on a missing path. A present `null` is always copied. A `value` template runs once in the source item's scope; computed copy plans remain supported.

HTTP response bodies and values selected by `item`, `this`, `either`, `map` and the array helpers are data. They are not implicitly executed again when they contain `{returns}`. Authored input expressions still evaluate normally, and `from` still evaluates definitions returned by its provider. This removes the previous second evaluation of selected data.

`text.from.splitting` accepts `value` and a non-empty `separator`. `text.from.date` accepts a computed date `value`, a Foundation date `format`, and optional `time_zone` (UTC by default). Formatting uses a Gregorian calendar and POSIX locale. `date.offset` adds a computed number of seconds to an epoch or ISO date before use, for example to format the next UTC day without native mapping code.

`text.from.number` formats a computed numeric `value`, with optional `currency`
and `locale`. For example, `{"value": 72.5, "currency": "GBP", "locale": "en_GB"}`
produces `£72.50`. Currency precision follows Foundation's currency rules; decimal
formatting omits `currency`. The default locale is `en_US_POSIX`, so evaluation
does not inherit a process's display locale. This uses immutable
[Foundation format styles](https://developer.apple.com/documentation/foundation/floatingpointformatstyle/currency)
(macOS 12 / iOS 15 or later); older systems report an unsupported-format error.
Native date values also retain their type through generic JSON slots in templates
and explanations, so `date` can compose with `this`, `map` and `text`.

`array_reduce` evaluates `next` once per element. During each iteration, the local `item` context contains `item`, `index`, and `accumulator`.

`explain` evaluates a value and returns an object containing `ok`, `value`, `summary`, and displayable `thoughts`. Set `mode` to `"foundation_model"` to add a natural-language `explanation` using Apple's on-device Foundation Models framework when it is available on iOS or macOS. `context` is optional user-facing context that helps the model explain what the computed value affects. On unsupported platforms, unavailable models, or generation failure, `explain` falls back to the trace-only payload. If the explained value fails, `explain` returns `ok: false` with an `error` string instead of throwing.

`literal` returns JSON unchanged, including nested expressions. For example,
`{"{returns}": {"literal": {"value": {"{returns}": {"from": {"reference": "later"}}}}}}`
returns the inner `from` expression as data. This is useful for deferred payloads
and values that have already been evaluated by another runtime. `get` can select
from a literal without evaluating the selected data again. An explicit null is
preserved; omitting `value` is an error.

## Philosophy

Compute is designed as an affordance for decoupling rule authorship from rule execution.

The aim is not to make every system depend on one central service with one complete view of the world. The aim is to let each part of a system express what it knows best:

- backends express product rules
- lexicons express shared names for domain concepts
- clients resolve device and user context
- private stores resolve private state
- custom keywords express domain-specific capabilities

This follows the broader Thousand Years idea of building tools that help people and systems express their own domains more independently.

## Development

Run the test suite with:

```sh
swift test
```
