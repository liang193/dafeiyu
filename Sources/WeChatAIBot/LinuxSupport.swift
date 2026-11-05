#if os(Linux)
import Foundation
import FoundationNetworking
import Glibc

struct LocalDeploymentAccess {
    let directory: URL
    let bridge: URL
    static var current: Self? {
        let env = ProcessInfo.processInfo.environment
        guard let path = env["DAFEIYU_LOCAL_ACCESS_DIR"], let config = env["DAFEIYU_BRIDGE_CONFIG_DIR"] else { return nil }
        return Self(directory: URL(fileURLWithPath: path), bridge: URL(fileURLWithPath: config))
    }
    private var file: URL { directory.appendingPathComponent("model-key.json") }
    private var baseURL: String { ProcessInfo.processInfo.environment["DAFEIYU_MODEL_BASE_URL"] ?? "https://api.deepseek.com" }
    func loadKey() throws -> String {
        guard FileManager.default.fileExists(atPath: file.path) else { return "" }
        let a = try FileManager.default.attributesOfItem(atPath: file.path)
        guard a[.type] as? FileAttributeType == .typeRegular,
              (a[.ownerAccountID] as? NSNumber)?.uint32Value == getuid(),
              ((a[.posixPermissions] as? NSNumber)?.intValue ?? 0o777) & 0o077 == 0 else {
            throw AppFailure.message("本机凭证权限异常，请检查私有凭证目录")
        }
        let value = try JSONSerialization.jsonObject(with: Data(contentsOf: file)) as? [String: String]
        return value?["baseURL"] == baseURL ? value?["key"] ?? "" : ""
    }
    func saveKey(_ key: String) throws {
        let fm = FileManager.default
        try fm.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        try fm.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
        try JSONSerialization.data(withJSONObject: ["key": key, "baseURL": baseURL]).write(to: file, options: .atomic)
        try fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
    }
    func clear() throws {
        if FileManager.default.fileExists(atPath: file.path) { try FileManager.default.removeItem(at: file) }
    }
    func oneBotToken(account: String, endpoint: String) throws -> String {
        guard endpoint == "ws://127.0.0.1:3001", !account.isEmpty, account.allSatisfy(\.isNumber) else {
            throw AppFailure.message("自动凭证仅用于本机 QQ 桥接，请检查地址与账号")
        }
        let perAccount = bridge.appendingPathComponent("onebot11_\(account).json")
        let source = FileManager.default.fileExists(atPath: perAccount.path) ? perAccount : bridge.appendingPathComponent("onebot11.json")
        let value = try JSONSerialization.jsonObject(with: Data(contentsOf: source)) as? [String: Any]
        let network = value?["network"] as? [String: Any]
        let servers = network?["websocketServers"] as? [[String: Any]] ?? []
        guard let token = servers.first(where: { String(describing: $0["port"] ?? "") == "3001" })?["token"] as? String, !token.isEmpty else {
            throw AppFailure.message("本机 OneBot 凭证未就绪")
        }
        return token
    }
    func napcatURL() throws -> String {
        let value = try JSONSerialization.jsonObject(with: Data(contentsOf: bridge.appendingPathComponent("webui.json"))) as? [String: Any]
        guard let token = value?["token"] as? String, !token.isEmpty else { throw AppFailure.message("QQ 登录凭证未就绪") }
        var url = URLComponents(string: "http://127.0.0.1:6099/webui/web_login")!
        url.queryItems = [URLQueryItem(name: "token", value: token)]
        return url.url!.absoluteString
    }
}

// Desktop observation is unused by the headless engine; all engine state still belongs to MainActor.
protocol ObservableObject: AnyObject {}
@propertyWrapper struct Published<Value> {
    var wrappedValue: Value
    init(wrappedValue: Value) { self.wrappedValue = wrappedValue }
}

// No plaintext fallback for macOS Keychain. Linux credentials are deliberately session-only.
enum Keychain {
    static func load(account: String = "api-key", allowAuthenticationUI: Bool = true) throws -> String { "" }
    static func save(_ value: String, account: String = "api-key") throws {
        throw AppFailure.message("Windows / Linux 版仅支持本次运行凭证，请取消保存到钥匙串")
    }
}

enum LinuxImages {
    static func process(_ data: Data, mode: String, options: [String: Int] = [:]) throws -> [Data] {
        guard data.count <= 20_000_000, let resources = RuntimeResources.directory else {
            throw AppFailure.message("图片过大或资源目录不可用")
        }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("dafeiyu-image-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        defer { try? FileManager.default.removeItem(at: directory) }
        let input = directory.appendingPathComponent("input"), output = directory.appendingPathComponent("output")
        let payload: [String: Any] = ["image": data.base64EncodedString(), "mode": mode, "options": options]
        try JSONSerialization.data(withJSONObject: payload).write(to: input)
        FileManager.default.createFile(atPath: output.path, contents: nil, attributes: [.posixPermissions: 0o600])
        let stdin = try FileHandle(forReadingFrom: input), stdout = try FileHandle(forWritingTo: output)
        defer { try? stdin.close(); try? stdout.close() }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/timeout")
        process.arguments = ["--signal=KILL", "20", "/usr/bin/python3", resources.appendingPathComponent("Linux/image-helper.py").path]
        process.standardInput = stdin; process.standardOutput = stdout; process.standardError = FileHandle.nullDevice
        try process.run(); process.waitUntilExit()
        guard process.terminationStatus == 0, let size = try output.resourceValues(forKeys: [.fileSizeKey]).fileSize, size <= 20_000_000,
              let encoded = try JSONSerialization.jsonObject(with: Data(contentsOf: output)) as? [String] else {
            throw AppFailure.message("图片格式、尺寸或处理时间不符合要求；请检查 Python Pillow 安装")
        }
        let images = encoded.compactMap { Data(base64Encoded: $0) }
        guard images.count == encoded.count, !images.isEmpty else { throw AppFailure.message("图片处理失败") }
        return images
    }
}
#endif
