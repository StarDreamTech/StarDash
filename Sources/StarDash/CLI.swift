import AppKit
import CoreFoundation

enum ControlJSON {
    static func data(_ value: Any) -> Data {
        (try? JSONSerialization.data(withJSONObject: value, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]))
            ?? Data("{\"ok\":false,\"error\":\"无法编码响应\"}".utf8)
    }

    static func object<T: Encodable>(_ value: T) throws -> Any {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return try JSONSerialization.jsonObject(with: encoder.encode(value))
    }
}

final class LocalControl {
    static var name: CFString { "tech.stardream.StarDash.control.\(getuid())" as CFString }
    private var port: CFMessagePort?
    private var source: CFRunLoopSource?
    let handle: ([String]) throws -> [String: Any]

    init(handle: @escaping ([String]) throws -> [String: Any]) { self.handle = handle }

    func start() throws {
        var context = CFMessagePortContext(version: 0, info: Unmanaged.passUnretained(self).toOpaque(), retain: nil, release: nil, copyDescription: nil)
        var occupied: DarwinBoolean = false
        let port = CFMessagePortCreateLocal(nil, Self.name, { _, _, data, info in
            var response: [String: Any]
            do {
                guard let data, CFDataGetLength(data) <= 65_536,
                      let arguments = try JSONSerialization.jsonObject(with: data as Data) as? [String],
                      let info else { throw dashError("CLI 请求无效或超过 64 KiB。") }
                let server = Unmanaged<LocalControl>.fromOpaque(info).takeUnretainedValue()
                response = try server.handle(arguments)
                response["ok"] = true
            } catch { response = ["ok": false, "error": error.localizedDescription] }
            return Unmanaged.passRetained(ControlJSON.data(response) as CFData)
        }, &context, &occupied)
        guard let port, !occupied.boolValue else { throw dashError("已有星盘实例占用控制通道。") }
        self.port = port
        source = CFMessagePortCreateRunLoopSource(nil, port, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
    }

    func stop() {
        if let port { CFMessagePortInvalidate(port) }
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        port = nil
        source = nil
    }

    static func send(_ arguments: [String]) throws -> Data? {
        guard let remote = CFMessagePortCreateRemote(nil, name) else { return nil }
        let request = try JSONSerialization.data(withJSONObject: arguments)
        guard request.count <= 65_536 else { throw dashError("CLI 请求不能超过 64 KiB。") }
        var reply: Unmanaged<CFData>?
        let result = CFMessagePortSendRequest(remote, 0, request as CFData, 5, 5, CFRunLoopMode.defaultMode.rawValue, &reply)
        guard result == kCFMessagePortSuccess, let reply else { throw dashError("星盘控制请求失败（\(result)），未确认操作结果。") }
        return reply.takeRetainedValue() as Data
    }

    deinit { stop() }
}

enum DashCLI {
    static let help = """
    星盘 CLI — 所有结果为 JSON；ok=false 时退出码为 1。
    stardash version | metrics | status
    stardash show [panel|floating]
    stardash settings get
    stardash settings set <compact|pinned|showCPU|showMemory|showNetwork|showBattery> <true|false>
    stardash awake start --minutes <1..1440> | awake stop
    stardash commands list
    stardash commands add --name <名称> --command <命令> [--icon <SF Symbol>]
    stardash commands edit <UUID> [--name <名称>] [--command <命令>] [--icon <SF Symbol>]
    stardash commands run <UUID> | commands remove <UUID>
    stardash startup status | startup enable | startup disable
    stardash update check | update install
    stardash restart | quit
    stardash skill path | skill install [codex|claude]

    除 metrics、version、skill 和离线 status 外，应用未运行时会在后台启动。
    commands run 只表示已交给终端，命令退出码请在终端查看。
    update 为异步任务；用 status 查看 update.state、message 和日志路径。
    """

    static func run(_ input: [String]) throws -> Int32 {
        var arguments = input
        if arguments.first == "--json" { arguments.removeFirst() }
        if arguments.isEmpty || arguments == ["help"] || arguments == ["--help"] || arguments == ["-h"] {
            print(help)
            return 0
        }
        if arguments == ["version"] || arguments == ["--version"] {
            return printResult(ControlJSON.data(["ok": true, "version": AppLifecycle.version]))
        }
        if arguments == ["metrics"] {
            let sampler = MetricsSampler()
            _ = sampler.sample()
            Thread.sleep(forTimeInterval: 1)
            return printResult(ControlJSON.data(["ok": true, "metrics": try ControlJSON.object(sampler.sample())]))
        }
        if arguments.first == "skill" { return printResult(try skill(Array(arguments.dropFirst()))) }
        try validate(arguments)
        if let reply = try LocalControl.send(arguments) { return printResult(reply) }
        if arguments == ["status"] {
            return printResult(ControlJSON.data(["ok": true, "running": false, "version": AppLifecycle.version]))
        }
        if arguments == ["quit"] { return printResult(ControlJSON.data(["ok": true, "running": false])) }
        let app = Bundle.main.bundleURL
        guard app.pathExtension == "app" else { throw dashError("请使用 StarDash.app 内的 stardash CLI，或先运行应用。") }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        process.arguments = ["-g", app.path, "--args", "--background"]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { throw dashError("无法启动星盘。") }
        for _ in 0..<50 {
            Thread.sleep(forTimeInterval: 0.1)
            if let reply = try LocalControl.send(arguments) { return printResult(reply) }
        }
        throw dashError("星盘启动后没有响应控制请求。")
    }

    private static func printResult(_ data: Data) -> Int32 {
        print(String(decoding: data, as: UTF8.self))
        let value = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        return value?["ok"] as? Bool == true ? 0 : 1
    }

    static func options(_ arguments: [String], allowed: Set<String>) throws -> [String: String] {
        guard arguments.count.isMultiple(of: 2) else { throw dashError("每个选项都必须紧跟一个值。") }
        var values: [String: String] = [:]
        for index in stride(from: 0, to: arguments.count, by: 2) {
            let key = arguments[index]
            guard allowed.contains(key), values[key] == nil else { throw dashError("未知或重复选项：\(key)") }
            values[key] = arguments[index + 1]
        }
        return values
    }

    static func validate(_ args: [String]) throws {
        if [["status"], ["show"], ["show", "panel"], ["show", "floating"], ["settings", "get"],
            ["awake", "stop"], ["commands", "list"], ["startup", "status"], ["startup", "enable"],
            ["startup", "disable"], ["update", "check"], ["update", "install"], ["restart"], ["quit"]].contains(args) { return }
        if args.count == 4, args[0...1] == ["settings", "set"],
           settingKeys.contains(args[2]), ["true", "false"].contains(args[3]) { return }
        if args.count == 4, Array(args.prefix(3)) == ["awake", "start", "--minutes"],
           let minutes = Int(args[3]), (1...1440).contains(minutes) { return }
        if args.count >= 2, args[0] == "commands" {
            if args[1] == "add" {
                let values = try options(Array(args.dropFirst(2)), allowed: ["--name", "--command", "--icon"])
                guard let name = values["--name"], let command = values["--command"] else { throw dashError("请提供 --name 和 --command。") }
                _ = try CommandShortcut(name: name, command: command, icon: values["--icon"] ?? "terminal.fill")
                return
            }
            if args.count >= 3, UUID(uuidString: args[2]) != nil {
                if ["run", "remove"].contains(args[1]), args.count == 3 { return }
                if args[1] == "edit" {
                    let values = try options(Array(args.dropFirst(3)), allowed: ["--name", "--command", "--icon"])
                    guard !values.isEmpty else { throw dashError("编辑命令至少需要一个选项。") }
                    return
                }
            }
        }
        throw dashError("参数无效。运行 stardash help 查看用法。")
    }

    static let settingKeys = ["compact", "pinned", "showCPU", "showMemory", "showNetwork", "showBattery"]

    private static func skill(_ arguments: [String]) throws -> Data {
        let source = Bundle.main.bundleURL.appendingPathComponent("Contents/Resources/skills/stardash")
        guard FileManager.default.fileExists(atPath: source.appendingPathComponent("SKILL.md").path) else {
            throw dashError("未找到随应用打包的 Skill，请先运行 scripts/build.sh。")
        }
        if arguments == ["path"] { return ControlJSON.data(["ok": true, "path": source.appendingPathComponent("SKILL.md").path]) }
        guard arguments == ["install"] || (arguments.count == 2 && arguments[0] == "install" && ["codex", "claude"].contains(arguments[1])) else {
            throw dashError("用法：stardash skill path 或 stardash skill install [codex|claude]")
        }
        let agent = arguments.count == 2 ? arguments[1] : "codex"
        let root: URL
        if agent == "codex", let directory = ProcessInfo.processInfo.environment["CODEX_HOME"], !directory.isEmpty {
            root = URL(fileURLWithPath: directory).appendingPathComponent("skills")
        } else {
            root = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(agent == "codex" ? ".codex/skills" : ".claude/skills")
        }
        let target = root.appendingPathComponent("stardash")
        guard !FileManager.default.fileExists(atPath: target.path) else {
            let existing = target.appendingPathComponent("SKILL.md")
            let bundled = try Data(contentsOf: source.appendingPathComponent("SKILL.md"))
            if let contents = try? Data(contentsOf: existing), contents == bundled {
                return ControlJSON.data(["ok": true, "path": existing.path, "changed": false])
            }
            throw dashError("目标 Skill 已存在且内容不同，未覆盖：\(target.path)")
        }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: source, to: target)
        return ControlJSON.data(["ok": true, "path": target.appendingPathComponent("SKILL.md").path, "changed": true])
    }
}
