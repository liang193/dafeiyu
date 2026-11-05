import Foundation
import BotCore

struct SocialChatCommand: Equatable {
    enum Action: String { case start, pause, status, login, identity, bind }
    var action: Action
    var platforms: [SocialPlatform]
    var keyword: String?
    var durationMinutes: Int?
    var error: String?
    var readOnly = false
    private static let platformPattern = "(?:b站|哔哩哔哩|bilibili|小红书)"
    private static func matches(_ pattern: String, _ text: String) -> [String]? {
        guard let regex = try? NSRegularExpression(pattern:pattern,options:.caseInsensitive),
              let match = regex.firstMatch(in:text,range:NSRange(text.startIndex...,in:text)) else { return nil }
        return (0..<match.numberOfRanges).map { i in Range(match.range(at:i),in:text).map { String(text[$0]) } ?? "" }
    }
    static func parse(_ input: String) -> Self? {
        guard input.count <= 300, !input.contains("\n") else { return nil }
        var text = input.trimmingCharacters(in:.whitespacesAndNewlines)
        text = text.replacingOccurrences(of:"^(?:(?:大肥鱼|鱼鱼|肥鱼)[，,：:\\s]*)?(?:(?:请|麻烦你|帮我|给我|你|现在|先|再)\\s*)*",with:"",options:.regularExpression)
        text = text.replacingOccurrences(of:"[。！!？?\\s]+$",with:"",options:.regularExpression)
        let lower = text.lowercased()
        let platforms: [SocialPlatform] = (lower.contains("小红书") ? [.xiaohongshu] : []) + ((lower.contains("b站") || lower.contains("bilibili") || lower.contains("哔哩哔哩")) ? [.bilibili] : [])
        if matches("^(?:暂停|停止|停下|停一下|停|(?:别|不要|不用)(?:再|去)?(?:刷|看|浏览))(?:一下|继续)?(?:\\s*"+platformPattern+"(?:和|、|与)?)*?(?:的)?(?:浏览|任务|了|吧|啦|了吧)*$",text) != nil {
            return Self(action:.pause,platforms:platforms.isEmpty ? SocialPlatform.allCases : platforms)
        }
        if matches("^(?:查看|查询|汇报|看看)?(?:所有平台|平台|"+platformPattern+")(?:的)?(?:状态|进度|刷到哪了|看得怎么样了|刷得怎么样了)(?:了|吧)?$",text) != nil {
            return Self(action:.status,platforms:platforms.isEmpty ? SocialPlatform.allCases : platforms)
        }
        for (pattern,action) in [("^(?:登录|打开|打开登录窗口)\\s*("+platformPattern+")(?:的)?(?:登录|登录窗口|账号)?(?:吧)?$",Action.login),
                                 ("^(?:核对|检查)\\s*("+platformPattern+")(?:的)?账号(?:吧)?$",.identity),
                                 ("^(?:确认绑定|绑定)\\s*("+platformPattern+")(?:的)?(?:账号)?(?:吧)?$",.bind)] {
            if matches(pattern,text) != nil, platforms.count == 1 { return Self(action:action,platforms:platforms) }
        }
        guard platforms.count == 1 else { return nil }
        let patterns = ["^(?:去|开始|继续)?(?:刷|逛|浏览|看看|看)(?:一会儿?|一下|一阵子)?\\s*("+platformPattern+")(.*)$",
                        "^(?:去|到|在)?\\s*("+platformPattern+")(?:上)?(?:刷|逛|浏览|看看|看)(.*)$"]
        guard let match = patterns.compactMap({ matches($0,text) }).first else { return nil }
        var topic = match[2].trimmingCharacters(in:.whitespaces)
        var duration: Int?
        if let time = matches("([0-9]{1,4}|[一二三四五六七八九十两半]{1,3})\\s*(分钟|小时)",topic) {
            let digits: [Character:Int] = ["一":1,"二":2,"两":2,"三":3,"四":4,"五":5,"六":6,"七":7,"八":8,"九":9]
            let number: Int
            if time[1] == "半" { number = time[2] == "小时" ? 30 : 0 }
            else if let value = Int(time[1]) { number = value * (time[2] == "小时" ? 60 : 1) }
            else {
                let parts = time[1].split(separator:"十",omittingEmptySubsequences:false)
                let value = parts.count == 2 ? (parts[0].first.flatMap { digits[$0] } ?? 1)*10 + (parts[1].first.flatMap { digits[$0] } ?? 0) : time[1].first.flatMap { digits[$0] } ?? 0
                number = value * (time[2] == "小时" ? 60 : 1)
            }
            duration = number
            topic = topic.replacingOccurrences(of:time[0]+"(?:后(?:停|停止)|就停)?",with:"",options:.regularExpression)
        }
        topic = topic.replacingOccurrences(of:"^(?:(?:上|的|相关的|关于|主题[：:]?|内容[：:]?|一些|一点|点|一下|一会儿?|一阵子|会儿)\\s*)+",with:"",options:.regularExpression)
        topic = topic.replacingOccurrences(of:"[吧呀哦啦，,。！!\\s]+$",with:"",options:.regularExpression)
        topic = topic.replacingOccurrences(of:"(?:相关的|相关)?(?:视频|笔记|帖子|内容)$",with:"",options:.regularExpression).trimmingCharacters(in:.whitespaces)
        let readOnly = topic.contains("只看不评论") || topic.contains("只浏览") || topic.contains("别评论") || topic.contains("不要评论")
        topic = topic.replacingOccurrences(of:"[，,\\s]*(?:只看不评论|只浏览|别评论|不要评论|顺便评论(?:两句)?|可以评论|自动评论)[吧。\\s]*",with:"",options:.regularExpression)
        let invalid = duration.map { !(5...120).contains($0) } == true ? "浏览时长支持 5–120 分钟。" : topic.count > 80 ? "兴趣主题最多 80 字。" : nil
        return Self(action:.start,platforms:platforms,keyword:topic.isEmpty ? nil : topic,durationMinutes:duration,error:invalid,readOnly:readOnly)
    }
    static func authorized(sender: String, config: QQConfig) -> Bool {
        sender == config.expectedSelfID || (config.socialControllerIDs ?? []).contains(sender)
    }
}

@MainActor enum SocialChatControl {
    nonisolated static let definition: [String:Any] = ["type":"function","function":["name":"manage_social_activity","description":"控制大肥鱼在 B站或小红书的自主活动。使用者允许自主浏览和评论，无需逐条审批。可开始浏览、暂停或查询真实进度。首次账号登录与绑定按实际状态提示，不编造完成。","parameters":["type":"object","properties":["platform":["type":"string","enum":["bilibili","xiaohongshu"]],"action":["type":"string","enum":["start","pause","status"]],"keyword":["type":"string","maxLength":80],"durationMinutes":["type":"integer","minimum":5,"maximum":120],"readOnly":["type":"boolean","description":"只有使用者明确要求只浏览、不评论时为 true"]],"required":["platform","action"]]]]
    static func modelCommand(_ arguments: String) throws -> SocialChatCommand {
        guard arguments.utf8.count <= 2048,
              let value = try JSONSerialization.jsonObject(with:Data(arguments.utf8)) as? [String:Any],
              let rawPlatform = value["platform"] as? String, let platform = SocialPlatform(rawValue:rawPlatform),
              let rawAction = value["action"] as? String, let action = SocialChatCommand.Action(rawValue:rawAction),
              [.start,.pause,.status].contains(action) else { throw AppFailure.message("平台控制参数无效") }
        let keyword = (value["keyword"] as? String)?.trimmingCharacters(in:.whitespacesAndNewlines)
        let duration = value["durationMinutes"] as? Int
        guard (keyword?.count ?? 0) <= 80, duration.map({(5...120).contains($0)}) ?? true else { throw AppFailure.message("主题或时长超出范围") }
        return SocialChatCommand(action:action,platforms:[platform],keyword:keyword?.isEmpty == true ? nil : keyword,durationMinutes:duration,readOnly:value["readOnly"] as? Bool ?? false)
    }
    static func execute(_ command: SocialChatCommand, workspace: SocialPlatforms, baseURL: String, model: String, key: String,
                        isCurrent: () -> Bool = { true }) async throws -> String {
        if let error = command.error { return error }
        var replies: [String] = []
        for platform in command.platforms {
            guard isCurrent() else { throw CancellationError() }
            let engine = workspace[platform]
            func action(_ name: String, settings: SocialSettings? = nil, expectedUID: String? = nil) -> SocialCommand {
                SocialCommand(requestID:UUID(),action:name,revision:engine.stored.revision,settings:settings,expectedUID:expectedUID,platform:platform)
            }
            switch command.action {
            case .pause: engine.pause(); replies.append(platform.name+"已暂停。")
            case .status:
                var status = platform.name+"："+engine.status+(engine.error.isEmpty ? "" : "；"+engine.error)
                if !engine.stored.records.isEmpty { status += "\n最近阅读摘要："+engine.stored.records.suffix(2).map { String($0.summary.prefix(180)) }.joined(separator:"；") }
                replies.append(status)
            case .login:
                try await engine.perform(action("login")); replies.append("已打开"+platform.name+"独立登录窗口，请扫码。完成后发送“核对"+platform.name+"账号”。")
            case .identity:
                try await engine.perform(action("identity")); replies.append(platform.name+"当前账号："+(engine.observed?.name ?? "未知")+"。确认是你的账号后，发送“确认绑定"+platform.name+"账号”。")
            case .bind:
                guard let observed = engine.observed else { throw AppFailure.message("请先发送“核对"+platform.name+"账号”") }
                try await engine.perform(action("bind",expectedUID:observed.id)); replies.append(platform.name+"账号已绑定，以后可直接从 QQ 启动浏览。")
            case .start:
                guard !engine.stored.boundUID.isEmpty else { throw AppFailure.message(platform.name+"尚未绑定账号。首次发送“登录"+platform.name+"”，扫码后再核对和确认绑定。") }
                guard !engine.running else { replies.append(platform.name+"已有任务在运行。换主题请先说“暂停"+platform.name+"”。"); continue }
                var settings = engine.stored.settings
                settings.mode = command.readOnly ? .browse : .auto
                if let topic = command.keyword { settings.keyword = topic }
                if let duration = command.durationMinutes { settings.durationMinutes = duration }
                if settings.baseURL == "https://api.deepseek.com" || settings.baseURL == baseURL {
                    guard !key.isEmpty else { throw AppFailure.message("QQ 模型凭证尚未就绪，请先连接 QQ") }
                    settings.baseURL = baseURL; settings.model = model
                }
                try await engine.perform(action("save",settings:settings))
                guard isCurrent() else { throw CancellationError() }
                if settings.baseURL == baseURL {
                    var credentials = action("credentials"); credentials.key = key; credentials.persistKey = false
                    try await engine.perform(credentials)
                }
                do {
                    try await engine.perform(action("start"))
                    guard isCurrent() else { engine.pause(); throw CancellationError() }
                } catch { if !isCurrent() { engine.pause() }; throw error }
                replies.append("已启动"+platform.name+"：主题“"+settings.keyword+"”，最多 "+String(settings.maxPosts)+" 条、"+String(settings.durationMinutes)+" 分钟。"+(command.readOnly ? "只浏览，不评论。" : "自动参与，可以自行决定评论。")+"可说“暂停"+platform.name+"”或“"+platform.name+"进度”。")
            }
        }
        return replies.joined(separator:"\n\n")
    }
}
