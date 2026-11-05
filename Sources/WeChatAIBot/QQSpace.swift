import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import BotCore

/// Text-only QZone publishing. Preparing a draft performs no external writes.
@MainActor final class QQSpace {
    static let shared = QQSpace()
    static var enabled: Bool { ProcessInfo.processInfo.environment["DAFEIYU_LOCAL_ACCESS_DIR"] != nil }
    nonisolated static let definition: [String:Any] = ["type":"function","function":["name":"prepare_qq_space_post","description":"准备一条 QQ 空间文字说说草稿，供使用者查看，不会实际发布。只能使用公开见闻或角色观点，不搬运好友私聊或群聊的私人内容。","parameters":["type":"object","properties":["text":["type":"string","maxLength":2000]],"required":["text"]]]]
    nonisolated static var definitions: [[String:Any]] {
        var result = [definition]
        if ProcessInfo.processInfo.environment["DAFEIYU_QZONE_PUBLISH"] == "1" {
            result.append(["type":"function","function":["name":"publish_qq_space_post","description":"发表一条 QQ 空间文字说说。使用者已允许自主发布，无需逐条审批。可表达角色观点或公开阅读见闻，不泄露好友、群聊私人信息，不将阅读冒充亲身经历。失败或结果未知不重试。","parameters":["type":"object","properties":["text":["type":"string","maxLength":2000]],"required":["text"]]]])
        }
        return result
    }
    struct Draft: Codable {
        var id: String; var text: String; var createdAt: Date
        var state: String = "draft"; var postID: String?; var detail: String = "未发布"
    }
    private var drafts: [Draft] = []
    private var loaded = false
    private let directory: URL?
    private let publishPermission: Bool?
    private let credentialProvider: ((QQConfig) async throws -> String)?
    init(directory: URL? = nil, publishPermission: Bool? = nil, credentialProvider: ((QQConfig) async throws -> String)? = nil) {
        self.directory = directory ?? ProcessInfo.processInfo.environment["DAFEIYU_DATA_DIR"].map { URL(fileURLWithPath:$0) }
        self.publishPermission = publishPermission; self.credentialProvider = credentialProvider
    }
    private var file: URL? {
        directory?.appendingPathComponent("qzone-drafts.json")
    }
    var publishingAllowed: Bool { publishPermission ?? (ProcessInfo.processInfo.environment["DAFEIYU_QZONE_PUBLISH"] == "1") }
    private func load() throws {
        guard !loaded else { return }
        if let file, FileManager.default.fileExists(atPath:file.path) { drafts = try JSONDecoder().decode([Draft].self,from:Data(contentsOf:file)) }
        for i in drafts.indices where drafts[i].state == "publishing" { drafts[i].state = "uncertain"; drafts[i].detail = "上次发布中断，结果未知；请在 QQ 空间核对，不会重发" }
        loaded = true
    }
    private func save() throws {
        guard let file else { return }
        try JSONEncoder().encode(drafts).write(to:file,options:.atomic)
        try FileManager.default.setAttributes([.posixPermissions:0o600],ofItemAtPath:file.path)
    }
    func snapshot() throws -> Data {
        try load()
        return try JSONSerialization.data(withJSONObject:["publishingAllowed":publishingAllowed,"status":publishingAllowed ? "已允许自主发布，也可手动发布草稿" : "发送规则待配置；可先准备草稿","drafts":try JSONSerialization.jsonObject(with:JSONEncoder().encode(drafts))])
    }
    func prepare(_ text: String) throws -> String {
        try load(); let text = text.trimmingCharacters(in:.whitespacesAndNewlines)
        guard !text.isEmpty, text.count <= 2000 else { throw AppFailure.message("说说正文需为 1 至 2000 字") }
        guard drafts.filter({$0.state == "draft"}).count < 50 else { throw AppFailure.message("待发布草稿已达 50 条，请先整理") }
        let id = UUID().uuidString
        drafts.append(Draft(id:id,text:text,createdAt:Date())); try save(); return id
    }
    private func credentials(_ config: QQConfig) async throws -> String {
        if let credentialProvider { return try await credentialProvider(config) }
        #if os(Linux)
        guard let access = LocalDeploymentAccess.current else { throw AppFailure.message("QQ 空间需要本机 QQ 桥接") }
        let connection = OneBotConnection(); defer { connection.close() }
        try await connection.connect(endpoint:config.endpoint,token:try access.oneBotToken(account:config.expectedSelfID,endpoint:config.endpoint))
        let login = try await connection.action("get_login_info")
        guard let data = login["data"] as? [String:Any], QQPolicy.identifier(data["user_id"]) == config.expectedSelfID else { throw AppFailure.message("QQ 账号核对失败") }
        let health = try await connection.action("get_status")
        guard (health["data"] as? [String:Any])?["online"] as? Bool == true else { throw AppFailure.message("请先登录 QQ") }
        let response = try await connection.action("get_credentials",params:["domain":"qzone.qq.com"])
        guard let cookies = (response["data"] as? [String:Any])?["cookies"] as? String, !cookies.isEmpty else { throw AppFailure.message("QQ 空间登录态不可用，请在 QQ 客户端登录空间") }
        return cookies
        #else
        throw AppFailure.message("当前部署未配置 QQ 空间登录")
        #endif
    }
    func check(_ config: QQConfig) async throws -> Data {
        let cookie = try await credentials(config)
        let ready = cookie.split(separator:";").contains { $0.trimmingCharacters(in:.whitespaces).hasPrefix("p_skey=") }
        return try JSONSerialization.data(withJSONObject:["ready":ready,"status":ready ? "QQ 账号已核对，空间凭证可用" : "已取得 Cookie，但缺少空间 p_skey，请先登录 QQ 空间"])
    }
    func publish(id: String, config: QQConfig, session: URLSession = .shared) async throws -> Data {
        try load()
        guard publishingAllowed else { throw AppFailure.message("发送规则尚未配置，当前只保存草稿") }
        guard !drafts.contains(where:{$0.state == "uncertain" || $0.state == "publishing"}) else { throw AppFailure.message("存在待核对的发布结果，请先处理") }
        guard let index = drafts.firstIndex(where:{$0.id == id}), drafts[index].state == "draft" else { throw AppFailure.message("草稿不存在或已提交，不会重复发布") }
        let cookie = try await credentials(config)
        let fields = Dictionary(cookie.split(separator:";").compactMap { pair -> (String,String)? in
            let parts = pair.split(separator:"=",maxSplits:1).map(String.init)
            guard parts.count == 2 else { return nil }; return (parts[0].trimmingCharacters(in:.whitespaces),parts[1])
        },uniquingKeysWith: { _,new in new })
        guard let skey = fields["p_skey"], !skey.isEmpty else { throw AppFailure.message("缺少空间 p_skey，未发布") }
        var hash: UInt32 = 5381
        for byte in skey.utf8 { hash = hash &+ (hash << 5) &+ UInt32(byte) }
        let gtk = hash & 0x7fffffff
        let url = URL(string:"https://user.qzone.qq.com/proxy/domain/taotao.qzone.qq.com/cgi-bin/emotion_cgi_publish_v6?g_tk=\(gtk)")!
        var request = URLRequest(url:url); request.httpMethod = "POST"; request.timeoutInterval = 30
        request.setValue(cookie,forHTTPHeaderField:"Cookie"); request.setValue("https://user.qzone.qq.com/\(config.expectedSelfID)",forHTTPHeaderField:"Referer")
        request.setValue("https://user.qzone.qq.com",forHTTPHeaderField:"Origin"); request.setValue("application/x-www-form-urlencoded; charset=UTF-8",forHTTPHeaderField:"Content-Type")
        let values = ["syn_tweet_verson":"1","paramstr":"1","who":"1","con":drafts[index].text,"feedversion":"1","ver":"1","ugc_right":"1","to_sign":"0","hostuin":config.expectedSelfID,"code_version":"1","richval":"","issyncweibo":"0","format":"json","qzreferrer":"https://user.qzone.qq.com/\(config.expectedSelfID)"]
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn:"-._~"))
        request.httpBody = Data(values.sorted(by:{$0.key < $1.key}).map { $0.key+"="+($0.value.addingPercentEncoding(withAllowedCharacters:allowed) ?? "") }.joined(separator:"&").utf8)
        guard drafts[index].state == "draft", !drafts.contains(where:{$0.state == "publishing" || $0.state == "uncertain"}) else { throw AppFailure.message("发布状态已改变，请刷新") }
        drafts[index].state = "publishing"; try save()
        do {
            let (data,response) = try await session.boundedData(for:request,limit:1_000_000)
            guard (response as? HTTPURLResponse)?.statusCode == 200,
                  let object = try JSONSerialization.jsonObject(with:data) as? [String:Any],
                  object["code"] as? Int == 0,
                  let result = object["data"] as? [String:Any],
                  let tid = result["tid"] as? String, !tid.isEmpty else { throw AppFailure.message("空间未返回可核对的发布 ID") }
            drafts[index].state = "accepted"; drafts[index].postID = tid; drafts[index].detail = "平台已接受发布，可在 QQ 空间核对"; try save()
        } catch {
            drafts[index].state = "uncertain"; drafts[index].detail = "发布结果未知，请在 QQ 空间核对；不会自动重试"; try? save()
            throw AppFailure.message(drafts[index].detail)
        }
        return try snapshot()
    }
}
