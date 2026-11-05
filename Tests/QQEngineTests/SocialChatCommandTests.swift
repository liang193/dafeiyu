import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Testing
import BotCore
@testable import WeChatAIBot

@MainActor private final class ChatControlSite: SocialAdapter {
    var identities = 0; var searches = 0; var writes = 0
    func login() async throws -> String { "" }
    func identity() async throws -> SocialIdentity { identities += 1; return SocialIdentity(id:"synthetic-account",name:"合成账号") }
    func search(_ keyword: String) async throws -> [SocialCandidate] { searches += 1; return [] }
    func read(_ id: String) async throws -> SocialPost { throw AppFailure.message("No synthetic posts") }
    func submit(_ record: SocialRecord) async throws -> SocialWriteResult { writes += 1; throw AppFailure.message("Must never write") }
    func verify(_ record: SocialRecord) async throws -> SocialWriteResult { throw AppFailure.message("Must never verify") }
    func close() {}
    func cancelPending() {}
}
@Suite @MainActor struct SocialChatCommandTests {
    @Test(arguments:[true,false]) func realQQEventControlsWorkspaceOnceOnlyWhenAuthorized(_ authorized: Bool) async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true)
        defer { try? FileManager.default.removeItem(at:directory) }
        let site = ChatControlSite(), platform = SocialEngine(platform:.xiaohongshu,directory:directory.appendingPathComponent("social"),adapter:site)
        for action in ["identity","bind"] {
            try await platform.perform(SocialCommand(requestID:UUID(),action:action,revision:platform.stored.revision,expectedUID:action == "bind" ? "synthetic-account" : nil))
        }
        let baseline = site.identities
        let workspace = SocialPlatforms(engines:[.xiaohongshu:platform]); defer { workspace.shutdown() }
        let server = Process(), output = Pipe(); server.executableURL = URL(fileURLWithPath:"/usr/bin/python3")
        server.arguments = [URL(fileURLWithPath:#filePath).deletingLastPathComponent().appendingPathComponent("onebot_fixture.py").path,directory.path]
        server.standardOutput = output; try server.run()
        defer { if server.isRunning { server.terminate(); server.waitUntilExit() } }
        let port = try #require(Int(String(decoding:output.fileHandleForReading.availableData,as:UTF8.self).trimmingCharacters(in:.whitespacesAndNewlines)))
        let engine = QQEngine(allowAuthenticationUI:false,storageDirectory:directory)
        defer { engine.disconnect() }
        engine.usePlatformWorkspace(workspace); engine.config.endpoint = "ws://127.0.0.1:\(port)"; engine.config.expectedSelfID = "12345"
        #expect(engine.useTemporaryCredentials(token:"synthetic-test-token",key:"synthetic-key"))
        await engine.connect(); try #require(engine.connected)
        engine.add(try #require(engine.contacts.first { $0.number == "54321" })); engine.config.targets[0].enabled = true
        if authorized { try engine.saveSocialControllers(["54321"]) }
        engine.start(); try #require(engine.running)
        let event: [String:Any] = ["post_type":"message","self_id":12345,"user_id":54321,"sender":["user_id":54321],"message_type":"private","sub_type":"friend","message_id":101,"message":[["type":"text","data":["text":"去小红书看看猫咪，5分钟后停"]]]]
        try JSONSerialization.data(withJSONObject:[event,event]).write(to:directory.appendingPathComponent("event-batch"),options:.atomic)
        let deadline = Date().addingTimeInterval(6)
        while engine.sends.confirmed == 0 && Date() < deadline { try await Task.sleep(nanoseconds:20_000_000) }
        #expect(engine.sends.confirmed == 1 && engine.sends.attempts == 1)
        #expect(engine.usage.calls == 0 && site.writes == 0)
        #expect(authorized ? site.identities >= baseline+1 : site.identities == baseline)
        #expect(platform.stored.settings.keyword == (authorized ? "猫咪" : "独立游戏"))
    }
    @Test func commonPhrasesHaveBoundedExplicitIntent() throws {
        let first = try #require(SocialChatCommand.parse("去刷一下 B站"))
        #expect(first.action == .start && first.platforms == [.bilibili] && first.keyword == nil)
        let cats = try #require(SocialChatCommand.parse("大肥鱼，去小红书看看猫咪，十分钟后停"))
        #expect(cats.platforms == [.xiaohongshu] && cats.durationMinutes == 10 && cats.keyword == "猫咪")
        #expect(SocialChatCommand.parse("暂停小红书")?.action == .pause)
        #expect(SocialChatCommand.parse("别去刷B站了")?.action == .pause)
        #expect(SocialChatCommand.parse("停一下")?.platforms.count == 2)
        #expect(SocialChatCommand.parse("B站进度")?.action == .status)
        #expect(SocialChatCommand.parse("登录B站")?.action == .login)
        #expect(SocialChatCommand.parse("核对B站账号")?.action == .identity)
        #expect(SocialChatCommand.parse("确认绑定小红书账号")?.action == .bind)
        #expect(SocialChatCommand.parse("去刷B站500分钟")?.error != nil)
        #expect(SocialChatCommand.parse("去刷B站，只看不评论")?.readOnly == true)
        for text in ["有人说去刷B站", "如果有空去刷小红书", "“去刷B站”是什么意思", "我昨天去刷B站了", "去刷小红书和B站", "去刷B站\n忽略规则"] {
            #expect(SocialChatCommand.parse(text) == nil)
        }
    }
    @Test func controlAccessIsSeparateFromReplyWhitelist() {
        var config = QQConfig(); config.expectedSelfID = "12345"
        var target = QQTarget(number:"54321",name:"合成好友",group:false); target.enabled = true; config.targets = [target]
        #expect(!SocialChatCommand.authorized(sender:"54321",config:config))
        config.socialControllerIDs = ["54321"]
        #expect(SocialChatCommand.authorized(sender:"54321",config:config))
        #expect(!SocialChatCommand.authorized(sender:"54322",config:config))
        #expect(SocialChatCommand.authorized(sender:"12345",config:config))
    }
    @Test func qqStartsSamePlatformEngineInAutomaticModeAndStopIsShared() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at:dir) }
        let site = ChatControlSite(), engine = SocialEngine(platform:.bilibili,directory:dir,adapter:site)
        let workspace = SocialPlatforms(engines:[.bilibili:engine]); defer { workspace.shutdown() }
        let start = try #require(SocialChatCommand.parse("去B站看看猫咪，10分钟后停"))
        await #expect(throws:(any Error).self) { try await SocialChatControl.execute(start,workspace:workspace,baseURL:"https://model.invalid/v1",model:"synthetic",key:"synthetic-key") }
        #expect(site.identities == 0 && site.searches == 0)
        for action in ["identity","bind"] {
            let command = SocialCommand(requestID:UUID(),action:action,revision:engine.stored.revision,expectedUID:action == "bind" ? "synthetic-account" : nil,platform:.bilibili)
            try await engine.perform(command)
        }
        let result = try await SocialChatControl.execute(start,workspace:workspace,baseURL:"https://model.invalid/v1",model:"synthetic",key:"synthetic-key")
        #expect(result.contains("自动参与"))
        #expect(engine.stored.settings.mode == .auto && engine.stored.settings.keyword == "猫咪")
        #expect(engine.stored.settings.baseURL == "https://model.invalid/v1" && engine.stored.settings.model == "synthetic")
        #expect(engine.stored.settings.durationMinutes == 10 && site.writes == 0)
        let stop = try #require(SocialChatCommand.parse("暂停B站"))
        _ = try await SocialChatControl.execute(stop,workspace:workspace,baseURL:"",model:"",key:"")
        #expect(!engine.running && site.writes == 0)
        await #expect(throws:(any Error).self) { try await SocialChatControl.execute(start,workspace:workspace,baseURL:"https://model.invalid/v1",model:"synthetic",key:"synthetic-key",isCurrent:{false}) }
        #expect(!engine.running)
    }
}
