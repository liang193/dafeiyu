import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Testing
import BotCore
@testable import WeChatAIBot

private final class QQSpaceFixture: URLProtocol, @unchecked Sendable {
    static let lock = NSLock()
    nonisolated(unsafe) static var requests = 0
    nonisolated(unsafe) static var ambiguous = false
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func stopLoading() {}
    override func startLoading() {
        Self.lock.lock(); Self.requests += 1; let ambiguous = Self.ambiguous; Self.lock.unlock()
        #expect(request.url?.host == "user.qzone.qq.com")
        #expect(request.httpMethod == "POST")
        #expect(request.value(forHTTPHeaderField:"Cookie") == "p_skey=synthetic-cookie; uin=o12345")
        #expect(request.value(forHTTPHeaderField:"Authorization") == nil)
        let data = Data((ambiguous ? #"{"code":0,"data":{}}"# : #"{"code":0,"data":{"tid":"synthetic-post"}}"#).utf8)
        client?.urlProtocol(self,didReceive:HTTPURLResponse(url:request.url!,statusCode:200,httpVersion:nil,headerFields:nil)!,cacheStoragePolicy:.notAllowed)
        client?.urlProtocol(self,didLoad:data); client?.urlProtocolDidFinishLoading(self)
    }
}
@Suite(.serialized) @MainActor struct QQSpaceTests {
    @Test func simulatedPublishIsSingleUseAndAmbiguityBlocksRetries() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true)
        defer { try? FileManager.default.removeItem(at:directory) }
        let configuration = URLSessionConfiguration.ephemeral; configuration.protocolClasses = [QQSpaceFixture.self]
        let session = URLSession(configuration:configuration); defer { session.invalidateAndCancel() }
        var config = QQConfig(); config.expectedSelfID = "12345"
        QQSpaceFixture.requests = 0; QQSpaceFixture.ambiguous = false
        let space = QQSpace(directory:directory,publishPermission:true,credentialProvider:{ _ in "p_skey=synthetic-cookie; uin=o12345" })
        let id = try space.prepare("合成测试说说")
        let success = try JSONSerialization.jsonObject(with:await space.publish(id:id,config:config,session:session)) as! [String:Any]
        #expect((success["drafts"] as! [[String:Any]])[0]["state"] as? String == "accepted")
        await #expect(throws:(any Error).self) { try await space.publish(id:id,config:config,session:session) }
        #expect(QQSpaceFixture.requests == 1)
        QQSpaceFixture.ambiguous = true
        let other = try space.prepare("合成未知结果")
        await #expect(throws:(any Error).self) { try await space.publish(id:other,config:config,session:session) }
        await #expect(throws:(any Error).self) { try await space.publish(id:other,config:config,session:session) }
        #expect(QQSpaceFixture.requests == 2)
        let restarted = QQSpace(directory:directory,publishPermission:true,credentialProvider:{ _ in "synthetic" })
        await #expect(throws:(any Error).self) { try await restarted.publish(id:other,config:config,session:session) }
        #expect(QQSpaceFixture.requests == 2)
    }
    @Test func draftsSurviveRestartAndNoRulesMeansNoPublish() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true)
        defer { try? FileManager.default.removeItem(at:directory) }
        let first = QQSpace(directory:directory)
        let id = try first.prepare("合成测试说说，绝不实际发布")
        let second = QQSpace(directory:directory)
        let value = try JSONSerialization.jsonObject(with:second.snapshot()) as! [String:Any]
        let drafts = value["drafts"] as! [[String:Any]]
        #expect(drafts.count == 1 && drafts[0]["id"] as? String == id)
        #expect(drafts[0]["state"] as? String == "draft")
        #expect(!second.publishingAllowed)
        await #expect(throws:(any Error).self) { try await second.publish(id:id,config:QQConfig()) }
        #expect(throws:(any Error).self) { try second.prepare("   ") }
        #expect(throws:(any Error).self) { try second.prepare(String(repeating:"字",count:2001)) }
        let after = try JSONSerialization.jsonObject(with:second.snapshot()) as! [String:Any]
        #expect((after["drafts"] as! [[String:Any]])[0]["state"] as? String == "draft")
    }
}
