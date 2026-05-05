import Foundation

public enum ComputeError: Error, Equatable, Sendable {
    case unresolvedReference(JSON)
    case recursionLimitExceeded
}

public struct JSONError: Error, Codable, Equatable, Hashable, Sendable, CustomStringConvertible, LocalizedError {
    public let message: String
    public let path: [String]

    public init(_ message: String, path: [String] = []) {
        self.message = message
        self.path = path
    }

    public init(_ error: any Error, path: [String] = []) {
        if let error = error as? JSONError {
            self = error
            return
        }
        if let error = error as? any LocalizedError, let description = error.errorDescription {
            self.init(description, path: path)
            return
        }
        self.init(String(describing: error), path: path)
    }

    public var description: String {
        guard !path.isEmpty else { return message }
        return "\(message) at \(path.joined(separator: "."))"
    }

    public var errorDescription: String? {
        description
    }
}

public enum Compute {
    @propertyWrapper
    public struct Context: Equatable, Sendable {
        public var item: JSON?
        public var wrappedValue: Context {
            ComputeTaskLocal.context
        }

        public init(item: JSON? = nil) {
            self.item = item
        }

        public func with(item: JSON) -> Context {
            var context = self
            context.item = item
            return context
        }
    }
}

enum ComputeTaskLocal {
    @TaskLocal static var context = Compute.Context()
}

extension Compute {
    public static var context: Context {
        ComputeTaskLocal.context
    }

    @discardableResult
    public static func withContext<Value: Sendable>(
        _ update: @Sendable (inout Context) throws -> Void,
        operation: @Sendable () async throws -> Value
    ) async rethrows -> Value {
        var context = ComputeTaskLocal.context
        try update(&context)
        return try await ComputeTaskLocal.$context.withValue(context, operation: operation)
    }

    @discardableResult
    public static func withContext<Value>(
        _ update: (inout Context) throws -> Void,
        operation: () throws -> Value
    ) rethrows -> Value {
        var context = ComputeTaskLocal.context
        try update(&context)
        return try ComputeTaskLocal.$context.withValue(context, operation: operation)
    }
}
