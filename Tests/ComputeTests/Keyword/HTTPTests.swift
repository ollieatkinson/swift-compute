import Foundation
import Compute
import Testing

@Suite(.serialized)
struct HTTPTests {

    @Test func performs_resolved_requests_as_an_async_returns_keyword() async throws {
        let json: JSON = [
            "{returns}": [
                "http": [
                    "request": [
                        "url": ["{returns}": ["item": ["url"]]],
                        "method": ["{returns}": ["item": ["method"]]],
                        "headers": [
                            "Authorization": ["{returns}": ["item": ["token"]]],
                            "Content-Type": "application/json",
                        ],
                        "body": [
                            "name": ["{returns}": ["item": ["name"]]],
                        ],
                        "timeout": ["{returns}": ["item": ["timeout"]]],
                    ],
                ],
            ],
        ]
        let context = Compute.Context(item: [
            "name": "Oliver",
            "method": "post",
            "timeout": 5,
            "token": "Bearer abc",
            "url": "https://example.com/users",
        ])
        let function = Compute.Keyword.HTTP.Function { request in
            #expect(request.url?.absoluteString == "https://example.com/users")
            #expect(request.httpMethod == "POST")
            #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer abc")
            #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/json")
            #expect(request.timeoutInterval == 5)
            #expect(request.httpBody.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: String] } == ["name": "Oliver"])

            return Compute.Keyword.HTTP.Response(
                data: Data(#"{"created":true}"#.utf8),
                url: request.url?.absoluteString,
                status: 201,
                headers: ["Content-Type": "application/json"]
            )
        }

        #expect(try await value(json, in: context, functions: [function]) == [
            "body": ["created": true],
            "headers": ["Content-Type": "application/json"],
            "status": 201,
            "url": "https://example.com/users",
        ])
    }

    @Test func recomputes_request_url_when_referenced_url_changes() async throws {
        let references = TestReferences()
        await references.set("users_url", to: "https://example.com/users")
        let requests = HTTPRequestProbe()
        let http = Compute.Keyword.HTTP.Function { request in
            await requests.response(for: request)
        }
        let json: JSON = [
            "{returns}": [
                "http": [
                    "request": [
                        "url": ["{returns}": ["from": ["reference": "users_url"]]],
                    ],
                ],
            ],
        ]
        let runtime = try runtime(json, functions: [Compute.Keyword.From.Function(references: references), http])
        var stream = runtime.run().makeAsyncIterator()

        await expectNext(&stream, equals: .success([
            "body": ["ok": true],
            "headers": [:],
            "status": 200,
            "url": "https://example.com/users",
        ]))

        await references.set("users_url", to: "https://example.com/people")
        await expectNext(&stream, equals: .success([
            "body": ["ok": true],
            "headers": [:],
            "status": 200,
            "url": "https://example.com/people",
        ]))

        let urls = await requests.urls
        #expect(urls.first == "https://example.com/users")
        #expect(urls.contains("https://example.com/people"))
        #expect(urls.last == "https://example.com/people")

        await references.finish()
        await runtime.cancel()
    }

    @Test func returns_plain_text_bodies_when_response_is_not_json() async throws {
        let function = Compute.Keyword.HTTP.Function { _ in
            Compute.Keyword.HTTP.Response(data: Data("accepted".utf8), status: 202)
        }

        #expect(try await value(
            [
                "{returns}": [
                    "http": [
                        "request": [
                            "url": "https://example.com",
                        ],
                    ],
                ],
            ],
            functions: [function]
        ) == [
            "body": "accepted",
            "headers": [:],
            "status": 202,
        ])
    }
}

private actor HTTPRequestProbe {
    private var requestedURLs: [String] = []

    var urls: [String] {
        requestedURLs
    }

    func response(for request: URLRequest) -> Compute.Keyword.HTTP.Response {
        let url = request.url?.absoluteString ?? ""
        requestedURLs.append(url)
        return Compute.Keyword.HTTP.Response(
            data: Data(#"{"ok":true}"#.utf8),
            url: url,
            status: 200
        )
    }
}
