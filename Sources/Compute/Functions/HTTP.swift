import Foundation

extension Keyword {
    public struct HTTP: Codable, Equatable, Sendable {
        public static let name = "http"

        public let request: Request

        public init(request: Request) {
            self.request = request
        }

        public struct Request: Codable, Equatable, Sendable {
            public let url: JSON
            public let method: JSON?
            public let headers: JSON?
            public let body: JSON?
            public let timeout: JSON?

            public init(
                url: JSON,
                method: JSON? = nil,
                headers: JSON? = nil,
                body: JSON? = nil,
                timeout: JSON? = nil
            ) {
                self.url = url
                self.method = method
                self.headers = headers
                self.body = body
                self.timeout = timeout
            }
        }

        public struct Response: Equatable, Sendable {
            public let data: Data
            public let url: String?
            public let status: Int?
            public let headers: [String: String]

            public init(
                data: Data = Data(),
                url: String? = nil,
                status: Int? = nil,
                headers: [String: String] = [:]
            ) {
                self.data = data
                self.url = url
                self.status = status
                self.headers = headers
            }

            init(data: Data, response: URLResponse) {
                let http = response as? HTTPURLResponse
                self.init(
                    data: data,
                    url: response.url?.absoluteString,
                    status: http?.statusCode,
                    headers: http?.allHeaderFields.reduce(into: [:]) { headers, field in
                        headers[String(describing: field.key)] = String(describing: field.value)
                    } ?? [:]
                )
            }

            var json: JSON {
                var object: [String: JSON] = [
                    "body": Keyword.HTTP.bodyJSON(from: data),
                    "headers": .object(headers.mapValues(JSON.string)),
                ]
                if let url {
                    object["url"] = .string(url)
                }
                if let status {
                    object["status"] = .int(status)
                }
                return .object(object)
            }
        }
    }
}

extension Keyword.HTTP {
    public struct Function: ReturnsKeyword {
        public let name = Keyword.HTTP.name

        private let perform: @Sendable (URLRequest) async throws -> Response

        public init(session: URLSession = .shared) {
            self.perform = { request in
                let (data, response) = try await session.data(for: request)
                return Response(data: data, response: response)
            }
        }

        public init(perform: @escaping @Sendable (URLRequest) async throws -> Response) {
            self.perform = perform
        }

        public func value(for input: JSON) async throws -> JSON {
            let http = try JSON.decoded(Keyword.HTTP.self, from: input)
            let request = try http.request.urlRequest()
            return try await perform(request).json
        }
    }
}
extension Keyword.HTTP.Request {
    func urlRequest() throws -> URLRequest {
        let urlString = try url.decode(String.self)
        guard let url = URL(string: urlString) else {
            throw JSONError("Invalid HTTP URL \(urlString)")
        }

        var request = URLRequest(url: url)
        request.httpMethod = try method?.decode(String.self).uppercased() ?? "GET"
        if let timeout {
            request.timeoutInterval = try timeout.decode(Double.self)
        }
        if let headers {
            for (name, value) in try headerFields(from: headers) {
                request.addValue(value, forHTTPHeaderField: name)
            }
        }
        if let body, body != .null {
            request.httpBody = try bodyData(from: body)
        }
        return request
    }

    private func headerFields(from json: JSON) throws -> [String: String] {
        guard case .object(let object) = json else {
            throw JSONError("HTTP headers must be an object")
        }
        return try object.mapValues { try $0.decode(String.self) }
    }

    private func bodyData(from json: JSON) throws -> Data {
        if case .string(let string) = json {
            return Data(string.utf8)
        }
        if case .object = json {
            return try JSONSerialization.data(withJSONObject: json.any)
        }
        if case .array = json {
            return try JSONSerialization.data(withJSONObject: json.any)
        }
        return Data(String(describing: json.any).utf8)
    }
}

extension Keyword.HTTP {
    static func bodyJSON(from data: Data) -> JSON {
        guard !data.isEmpty else { return .null }
        if let value = try? JSONSerialization.jsonObject(with: data, options: .fragmentsAllowed) {
            return JSON(value)
        }
        if let string = String(data: data, encoding: .utf8) {
            return .string(string)
        }
        return .string(data.base64EncodedString())
    }
}
