import Foundation
import IOKit.pwr_mgt

enum SelfTests {
    private static func check(_ value: @autoclosure () -> Bool, _ message: String) throws {
        guard value() else { throw NSError(domain: "StarDash.SelfTest", code: 1, userInfo: [NSLocalizedDescriptionKey: message]) }
    }

    static func run() throws {
        let old = CPUTicks(values: [100, 100, 100, 100])
        let new = CPUTicks(values: [120, 110, 160, 110])
        try check(new.usage(since: old) == 40, "CPU 忙闲计算错误")
        try check(old.usage(since: old) == nil, "CPU 无增量时不能显示假零值")
        let wrapOld = CPUTicks(values: [UInt32.max - 1, 10, 10, 10])
        let wrapNew = CPUTicks(values: [1, 11, 13, 11])
        try check(wrapNew.usage(since: wrapOld) == 62.5, "CPU 计数溢出处理错误")

        let previous: [UInt16: NetworkCounter] = [1: .init(received: 1000, sent: 2000)]
        let current: [UInt16: NetworkCounter] = [1: .init(received: 3000, sent: 3000)]
        let rate = NetworkRate.between(previous, current, seconds: 2)
        try check(rate?.download == 1000 && rate?.upload == 500, "网速方向或采样间隔错误")
        try check(NetworkRate.between(previous, current, seconds: 0) == nil, "零采样间隔应拒绝")
        let reset: [UInt16: NetworkCounter] = [1: .init(received: 1, sent: 1), 2: .init(received: 900000, sent: 900000)]
        let resetRate = NetworkRate.between(previous, reset, seconds: 1)
        try check(resetRate?.download == 0 && resetRate?.upload == 0, "接口重置或新增不应产生流量尖峰")
        try check(MetricText.countdown(-1) == "00:00:00", "倒计时不能为负")
        try check(MetricText.countdown(3661) == "01:01:01", "倒计时格式错误")
        try check(MetricText.rate(1_500_000) == "1.5 MB/s", "流量单位错误")
        try check(MetricText.rate(.nan) == "不可用", "无效数据不能显示为零")

        let sampler = MetricsSampler()
        let first = sampler.sample()
        try check(first.cpuPercent == nil && first.network == nil, "首次采样必须等待增量")
        Thread.sleep(forTimeInterval: 0.2)
        let live = sampler.sample()
        try check(live.cpuPercent.map { (0...100).contains($0) } == true, "本机 CPU 采集失败")
        try check(live.memory.map { $0.used > 0 && $0.used <= $0.total } == true, "本机内存采集失败")
        try check(live.network.map { $0.download >= 0 && $0.upload >= 0 } == true, "本机网络采集失败")
        try check(live.battery.present != nil, "本机供电来源读取失败")
        let awake = KeepAwake()
        awake.start(seconds: -1)
        try check(!awake.isActive && awake.message != nil, "无效防休眠时间应拒绝")
        print("PASS: 16 项计算、异常边界及本机采集检查")
        try commands()
    }

    private static func commands() throws {
        let suite = "StarDash.SelfTest.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let model = AppModel(defaults: defaults)
        let command = try CommandShortcut(name: "  中文命令  ", command: "printf '%s\\n' \"it's fine\"\npwd", icon: "unknown")
        try check(command.name == "中文命令" && command.icon == "terminal.fill", "名称清理或图标回退错误")
        try check((try? CommandShortcut(name: " ", command: "pwd")) == nil, "空名称必须拒绝")
        try check((try? CommandShortcut(name: "测试", command: "\n ")) == nil, "空命令必须拒绝")
        try check((try? CommandShortcut(name: "测试", command: "pwd\0")) == nil, "空字符必须拒绝")
        try model.saveCommand(command)
        try check(AppModel(defaults: defaults).commands == [command], "命令重启恢复错误")
        let edited = try CommandShortcut(id: command.id, name: "已编辑", command: "pwd")
        try model.saveCommand(edited)
        try check(model.commands == [edited], "编辑不能新增重复项")
        try model.deleteCommand(edited)
        try check(AppModel(defaults: defaults).commands.isEmpty, "删除命令未保存")
        let corrupt = Data("not-json".utf8)
        defaults.set(corrupt, forKey: "commands")
        let damaged = AppModel(defaults: defaults)
        try check(damaged.commandMessage != nil, "损坏的命令数据必须提示")
        var rejected = false
        do { try damaged.saveCommand(command) } catch { rejected = true }
        try check(rejected && defaults.data(forKey: "commands") == corrupt && damaged.commands.isEmpty,
                  "保存失败必须保留原始数据及内存状态")

        let manager = FileManager.default
        let root = manager.temporaryDirectory.appendingPathComponent("StarDash-Test-\(UUID().uuidString)")
        defer { try? manager.removeItem(at: root) }
        let home = root.appendingPathComponent("中文 home's folder")
        try manager.createDirectory(at: home, withIntermediateDirectories: true)
        let output = root.appendingPathComponent("result.txt")
        let body = "printf '%s\\n' \"it's fine\" '中文 空格' '$HOME $(exit 9) `exit 8`' > \(TerminalCommand.shellQuote(output.path))\npwd >> \(TerminalCommand.shellQuote(output.path))\nexit 7"
        let probe = try CommandShortcut(name: "不要执行 $(exit 99)", command: body)
        let script = try TerminalCommand.prepare(probe)
        defer { try? manager.removeItem(at: script.deletingLastPathComponent()) }
        let attributes = try manager.attributesOfItem(atPath: script.path)
        try check((attributes[.posixPermissions] as? NSNumber)?.intValue == 0o700, "命令脚本必须仅本人可读写执行")
        try TerminalCommand.script(for: probe, home: home).write(to: script, atomically: true, encoding: .utf8)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = [script.path]
        var environment = ProcessInfo.processInfo.environment
        environment["ZDOTDIR"] = root.path
        process.environment = environment
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        let result = try String(contentsOf: output, encoding: .utf8)
        try check(result == "it's fine\n中文 空格\n$HOME $(exit 9) `exit 8`\n\(home.path)\n",
                  "命令原文、引号、Unicode、多行或工作目录未正确传递")
        try check(process.terminationStatus == 7, "命令退出码未保留")
        try check(!manager.fileExists(atPath: script.deletingLastPathComponent().path), "执行后未清理临时脚本")
        print("PASS: 命令校验、增改删恢复、损坏数据保护、权限、真实 zsh 转义执行、目录、退出码及临时清理")
    }

    static func power() throws {
        let awake = KeepAwake()
        defer { awake.stop() }
        awake.start(seconds: 2)
        try check(awake.isActive, awake.message ?? "创建防休眠断言失败")
        RunLoop.main.run(until: Date().addingTimeInterval(0.25))
        let active = try systemAssertionIsListed()
        try check(active, "系统防休眠状态未开启")
        Thread.sleep(forTimeInterval: 3.2)
        // CopyProperties retains the creation level after timeout; check powerd's effective state instead.
        let stillActive = try systemAssertionIsListed()
        try check(!stillActive, "主线程暂停时，系统未按时结束防休眠")
        RunLoop.main.run(until: Date().addingTimeInterval(1.2))
        try check(!awake.isActive && awake.deadline == nil, "防休眠到期未清理")
        awake.start(seconds: 10)
        try check(awake.isActive, "第二次创建断言失败")
        awake.stop()
        try check(!awake.isActive && awake.remaining == 0, "手动结束未清理")
        let afterStop = try systemAssertionIsListed()
        try check(!afterStop, "手动结束后系统仍持有防休眠断言")
        awake.stop()
        try check(!awake.isActive, "重复结束应保持关闭")
        print("PASS: 防休眠创建、主线程暂停时系统超时、到期清理、手动结束与重复清理")
    }

    private static func systemAssertionIsListed() throws -> Bool {
        let process = Process()
        let output = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/pmset")
        process.arguments = ["-g", "assertions"]
        process.standardOutput = output
        process.standardError = output
        try process.run()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        try check(process.terminationStatus == 0, "无法读取系统电源断言")
        return String(decoding: data, as: UTF8.self).contains("pid \(ProcessInfo.processInfo.processIdentifier)(")
    }
}
