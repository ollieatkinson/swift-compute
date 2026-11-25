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

[`Computer.default`](Sources/Compute/Computer.swift) registers these `{returns}` keywords:

- Values: `this`, `item`, `literal`
- Logic: `yes`, `not`, `either`, `exists`
- Comparisons: `comparison`, `approximately_equal`
- Collections: `count`, `contains`, `get`, `map`
- Arrays: `array_map`, `array_filter`, `array_group`, `array_reduce`, `array_slice`, `array_sort`, `array_subscript`, `array_zip`
- Dates and time: `date`, `calendar`, `seconds`
- Text and HTTP: `text`, `http`
- Diagnostics: `error`, `explain`

`from` (references) and `eval` (JavaScript) require separate registration.

## Philosophy

Compute is designed as an affordance for decoupling rule authorship from rule execution.

The aim is not to make every system depend on one central service with one complete view of the world. The aim is to let each part of a system express what it knows best:

- backends express product rules
- lexicons express shared names for domain concepts
- clients resolve device and user context
- private stores resolve private state
- custom keywords express domain-specific capabilities

This follows the broader Thousand Years idea of building tools that help people and systems express their own domains more independently.

## JSON encoding

`JSON.encoded(value)` freezes an `Encodable` value through Foundation's JSON
encoder. Empty objects and arrays remain distinct from null, nested containers
work normally, and encoding errors propagate. Dates use seconds since 1970,
URLs use their Codable string representation, and byte data uses arrays.
Numbers normalize as they do in `JSON(data:)`; native runtime atoms keep their
types until this encoding boundary. A native date wrapped in `JSON` also respects
the date strategy when passed to a caller-configured `JSONEncoder`.
Wire decoding keeps signed integer precision and checks floating-point ranges
before converting to `Int`, avoiding NSNumber's clamping or unsigned wrapping.

Decoding an existing `JSON` as `JSON` is an identity operation, including through
generic `decode`/`decoded` calls and computed JSON slots. It preserves native
atoms and opaque data without a Foundation conversion or another decoder pass.
Other destination types reuse the existing in-memory Codable containers. Typed
numeric fields reject boolean/string coercions, and integer conversions reject
fractions and out-of-range values. Floating-point
conversion accepts integer inputs and rejects newly introduced overflow. These
checks also apply inside typed arrays and synthesized fields. Native-value and
URL conversions retain their existing path. String conversions, including regex
match operands, keep their existing behaviour. Boxed JSON fields retain their
native atoms until requested. Only coercing string reads keep their existing
Foundation-container conversion; no JSON text round trip is added.

A computed `Double?` slot can be absent/null, but a malformed present value reports
its field route and remains recoverable. `true` is not a numeric default. Existing
AnyCoding policies for optional container fields are unchanged. Use explicit
expressions when numeric conversion is intended.

## Development

Run the test suite with:

```sh
swift test
```
