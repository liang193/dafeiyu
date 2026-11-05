import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Testing
@testable import WeChatAIBot
import BotCore

private final class ModelEndpointFixture: URLProtocol, @unchecked Sendable {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func stopLoading() {}
    override func startLoading() {
        let url = request.url!
        #expect(url.host == "model-fixture.example")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer synthetic")
        let data: Data
        if request.httpMethod == "GET" {
            #expect(url.path == "/compatible-mode/v1/models")
            data = Data(#"{"data":[{"id":"fixture-model"}]}"#.utf8)
        } else {
            #expect(url.path == "/compatible-mode/v1/chat/completions")
            var body = request.httpBody ?? Data()
            if let stream = request.httpBodyStream {
                stream.open(); defer { stream.close() }
                var bytes = [UInt8](repeating: 0, count: 4096)
                while stream.hasBytesAvailable {
                    let count = stream.read(&bytes, maxLength: bytes.count)
                    if count <= 0 { break }
                    body.append(contentsOf: bytes.prefix(count))
                }
            }
            let object = try! JSONSerialization.jsonObject(with: body) as! [String: Any]
            #expect(object["model"] as? String == "fixture-model")
            #expect(object["thinking"] == nil)
            #expect(object["reasoning_effort"] == nil)
            #expect(object["max_tokens"] as? Int == 500)
            data = Data(#"{"choices":[{"message":{"content":"hello"},"finish_reason":"stop"}]}"#.utf8)
        }
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }
}

@Suite struct ModelEndpointTests {
    @Test @MainActor func compatibleEndpointPreservesPrefixWithoutVendorParameters() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [ModelEndpointFixture.self]
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        let client = DeepSeekClient(baseURL: "https://model-fixture.example/compatible-mode/v1", session: session)
        var config = BotConfig(); config.model = "fixture-model"
        let result = try await client.reply(key: "synthetic", config: config, rule: ChatRule(name: "fixture"),
            history: [], text: "hi", thinkingEnabled: true, reserve: {})
        #expect(result.text == "hello")
        let models = try await client.models(key: "synthetic")
        #expect(models == ["fixture-model"])
    }

    @Test(arguments: ["http://model-fixture.example/v1", "https://user:password@model-fixture.example/v1",
                      "https://model-fixture.example/v1?key=synthetic", "https://model-fixture.example/v1#fragment"])
    func invalidEndpointNeverReceivesCredentials(baseURL: String) async {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [ModelEndpointFixture.self]
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        do {
            _ = try await DeepSeekClient(baseURL: baseURL, session: session).models(key: "synthetic")
            Issue.record("Invalid endpoint was accepted")
        } catch {
            #expect(error.localizedDescription.contains("HTTPS Base URL"))
        }
    }
}
