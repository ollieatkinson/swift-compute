import Foundation

public struct JSONError: Swift.Error, Codable, Equatable, Hashable, Sendable,
    CustomStringConvertible, LocalizedError
{
    public let message: String
    public let path: [String]

    public init(_ message: String, path: [String] = []) {
        self.message = message
        self.path = path
    }

    public init(_ error: any Swift.Error, path: [String] = []) {
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
