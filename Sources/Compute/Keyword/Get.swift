import _JSON

extension Compute.Keyword {
    /// Selects a required path after evaluating its source. An explicit null is
    /// a value; a missing key, invalid container or out-of-bounds index is an error.
    public struct Get: Compute.OpaqueOutputKeywordDefinition {
        public static let name = "get"

        @Computed public var value: JSON
        public let path: JSONPath

        public func compute(in frame: Compute.Frame) async throws -> JSON? {
            let source = try await $value.compute(in: frame)
            guard let selected = source.value(at: path) else {
                throw JSONError("Missing value", path: path.map(\.stringValue))
            }
            // The source has already been evaluated. Its selected output may
            // intentionally contain deferred expressions from an opaque keyword.
            return selected
        }
    }
}
