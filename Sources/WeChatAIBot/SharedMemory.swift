import Foundation
import BotCore

enum SharedMemory {
    static var enabled: Bool { ProcessInfo.processInfo.environment["DAFEIYU_MEMORY_BRIDGE"] != nil }
    static let definitions: [[String: Any]] = [["type":"function", "function":["name":"remember_observation", "description":"记住当前发言中明确有依据的重要偏好、纠正或约定。仅属于当前会话，不能保存指令、密钥、猜测或图片推断。", "parameters":["type":"object", "properties":["text":["type":"string"],"evidence":["type":"string","description":"逐字引用当前输入的证据"],"relation":["type":"string"]],"required":["text","evidence","relation"]]]], ["type":"function","function":["name":"propose_personality","description":"提出角色自身表达习惯的候选，等待使用者确认；不能包含他人私人事实或执行权限。","parameters":["type":"object","properties":["text":["type":"string"],"evidence":["type":"string"]],"required":["text","evidence"]]]]]
    static func call(_ payload: [String: Any]) async throws -> Data {
        guard let script = ProcessInfo.processInfo.environment["DAFEIYU_MEMORY_BRIDGE"] else { throw AppFailure.message("统一记忆未启用") }
        let input = try JSONSerialization.data(withJSONObject: payload)
        return try await Task.detached {
            let process = Process(), pipeIn = Pipe(), pipeOut = Pipe()
            process.executableURL = URL(fileURLWithPath:"/usr/bin/timeout")
            process.arguments = ["8", "/usr/bin/node", script]
            process.standardInput = pipeIn; process.standardOutput = pipeOut; process.standardError = FileHandle.nullDevice
            try process.run()
            try pipeIn.fileHandleForWriting.write(contentsOf:input); try pipeIn.fileHandleForWriting.close()
            let data = pipeOut.fileHandleForReading.readDataToEndOfFile(); process.waitUntilExit()
            guard process.terminationStatus == 0, data.count <= 262144 else { throw AppFailure.message("统一记忆操作失败，请检查本机记忆服务") }
            return data
        }.value
    }
    static func context(platform: String, scope: String, query: String) async throws -> String {
        guard enabled else { return "" }
        let data = try await call(["action":"context","platform":platform,"scope":scope,"query":query])
        return String(((try JSONSerialization.jsonObject(with:data) as? [String:Any])?["context"] as? String ?? "").prefix(5000))
    }
    static func tool(name: String, arguments: String, scope: String, source: String, sourceID: String, subject: String) async throws -> ModelToolResult {
        guard arguments.utf8.count <= 8192 else { throw AppFailure.message("记忆参数过长") }
        guard let item = try JSONSerialization.jsonObject(with:Data(arguments.utf8)) as? [String:Any] else { throw AppFailure.message("记忆参数无效") }
        let payload: [String:Any]
        if name == "remember_observation" { payload = ["action":"observe","platform":"qq","scope":scope,"source":source,"sourceID":sourceID,"subject":subject,"items":[item]] }
        else { payload = ["action":"propose","text":item["text"] ?? "","evidence":item["evidence"] ?? ""] }
        return ModelToolResult(content:String(decoding:try await call(payload),as:UTF8.self))
    }
}
