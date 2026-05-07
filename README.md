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

The default computer includes keywords for:

- boolean checks with `yes`, `not`, and `either`
- comparisons with `comparison`
- explanations with `explain`
- explicit failures with `error`
- collection helpers like `count`, `contains`, `map`, `array_map`, `array_filter`, `array_group`, `array_reduce`, `array_slice`, `array_sort`, `array_subscript`, and `array_zip`
- item lookup with `item`
- text formatting with `text`
- HTTP values with `http`

Reference values can be added with `Compute.Keyword.From.Function(references:)`. JavaScript evaluation can be added explicitly with `Compute.Keyword.Eval.function`.

Custom keywords can be added by conforming to `Compute.KeywordDefinition` or `AnyReturnsKeyword`, declaring a `name`, and passing them into `Compute.Runtime`.

`array_reduce` evaluates `next` once per element. During each iteration, the local `item` context contains `item`, `index`, and `accumulator`.

`explain` evaluates a value and returns an object containing `ok`, `value`, `summary`, and displayable `thoughts`. Set `mode` to `"foundation_model"` to add a natural-language `explanation` using Apple's on-device Foundation Models framework when it is available on iOS or macOS. `context` is optional user-facing context that helps the model explain what the computed value affects. On unsupported platforms, unavailable models, or generation failure, `explain` falls back to the trace-only payload. If the explained value fails, `explain` returns `ok: false` with an `error` string instead of throwing.

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
