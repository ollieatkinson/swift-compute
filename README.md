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

let runtime = ComputeRuntime(
    document: document,
    functions: [
        Keyword.From.Function(references: deviceReferences),
    ]
)

let value = try await runtime.value()

// value == true
```

The document can come from a backend. The values behind `subject.age` and `accessibility.voiceOver.enabled` can stay on the device, or in a private store that only the device can access.

## Built-in Keywords

The default computer includes keywords for:

- boolean checks with `yes`, `not`, and `either`
- comparisons with `comparison`
- explicit failures with `error`
- collection helpers like `count`, `contains`, `map`, `array_map`, `array_filter`, `array_group`, `array_slice`, `array_sort`, `array_subscript`, and `array_zip`
- item lookup with `item`
- text formatting with `text`
- HTTP values with `http`

Reference values can be added with `Keyword.From.Function(references:)`. JavaScript evaluation can be added explicitly with `Keyword.Eval.function`.

Custom keywords can be added by conforming to `ComputeKeyword` or `AnyReturnsKeyword`, declaring a `name`, and passing them into `ComputeRuntime`.

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
