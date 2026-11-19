import AppKit
import Combine
import ServiceManagement

func dashError(_ message: String) -> NSError {
    NSError(domain: "StarDash", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
}

struct ReleaseVersion: Comparable, Equatable {
    let parts: [Int]

    init?(_ text: String) {
        let value = text.hasPrefix("v") ? String(text.dropFirst()) : text
        let components = value.split(separator: ".", omittingEmptySubsequences: false)
        guard components.count == 3,
              components.allSatisfy({ !$0.isEmpty && $0.allSatisfy({ $0.isASCII && $0.isNumber }) }),
              components.compactMap({ Int($0) }).count == 3 else { return nil }
        parts = components.compactMap { Int($0) }
    }

    static func < (lhs: Self, rhs: Self) -> Bool { lhs.parts.lexicographicallyPrecedes(rhs.parts) }
}

struct PublishedRelease: Decodable {
    let tag_name: String
    let draft: Bool
    let prerelease: Bool

    func newer(than current: String) throws -> Bool {
        guard !draft, !prerelease, let latest = ReleaseVersion(tag_name), let installed = ReleaseVersion(current) else {
            throw dashError("发布版本号无效，未执行更新。")
        }
        return latest > installed
    }
}

enum HomebrewUpdate {
    static let cask = "stardreamtech/tap/stardash"
    static var executable: URL? {
        ["/opt/homebrew/bin/brew", "/usr/local/bin/brew"].first {
            FileManager.default.isExecutableFile(atPath: $0)
        }.map { URL(fileURLWithPath: $0) }
    }

    static func run(_ executable: URL, _ arguments: [String], log: FileHandle? = nil) throws -> Data {
        let process = Process()
        let output = Pipe()
        process.executableURL = executable
        process.arguments = arguments
        process.standardOutput = log ?? output.fileHandleForWriting
        process.standardError = log ?? FileHandle.nullDevice
        process.standardInput = FileHandle.nullDevice
        var environment = ProcessInfo.processInfo.environment
        environment["HOMEBREW_NO_ENV_HINTS"] = "1"
        process.environment = environment
        try process.run()
        let data = log == nil ? output.fileHandleForReading.readDataToEndOfFile() : Data()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw dashError("Homebrew 执行失败（\(process.terminationStatus)），当前星盘继续运行。请查看更新日志。")
        }
        return data
    }

    static func installedVersion(_ data: Data) throws -> String {
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let casks = object["casks"] as? [[String: Any]], casks.count == 1,
              casks[0]["token"] as? String == "stardash",
              casks[0]["tap"] as? String == "stardreamtech/tap",
              let installed = casks[0]["installed"] as? String, !installed.isEmpty else {
            throw dashError("星盘尚未通过官方 Homebrew 源安装。发布后请先安装 stardreamtech/tap/stardash。")
        }
        return installed
    }
}

final class AppLifecycle: ObservableObject {
    static var version: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.3.0" }
    @Published private(set) var loginStatus = "disabled"
    @Published private(set) var updateState = "idle"
    @Published private(set) var latestVersion: String?
    @Published private(set) var message: String?
    @Published private(set) var busy = false
    var logURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs/StarDash/update.log")
    }

    init() { refreshLoginStatus() }

    func refreshLoginStatus() {
        switch SMAppService.mainApp.status {
        case .enabled: loginStatus = "enabled"
        case .requiresApproval: loginStatus = "requires_approval"
        case .notRegistered: loginStatus = "disabled"
        case .notFound: loginStatus = "unavailable"
        @unknown default: loginStatus = "unknown"
        }
    }

    func setStartAtLogin(_ enabled: Bool) throws {
        guard Bundle.main.bundleURL.pathExtension == "app" else { throw dashError("请从 StarDash.app 设置开机自启动。") }
        do {
            if enabled { try SMAppService.mainApp.register() }
            else { try SMAppService.mainApp.unregister() }
            refreshLoginStatus()
            message = loginStatus == "requires_approval" ? "请在系统设置 → 通用 → 登录项中允许星盘。" : nil
        } catch {
            refreshLoginStatus()
            throw dashError("无法修改开机自启：\(error.localizedDescription)")
        }
    }

    func showError(_ error: Error) { message = error.localizedDescription }

    func checkForUpdates() throws {
        guard !busy else { throw dashError("正在检查或安装更新，请稍后再试。") }
        busy = true
        updateState = "checking"
        message = "正在检查更新…"
        var request = URLRequest(url: URL(string: "https://api.github.com/repos/StarDreamTech/StarDash/releases/latest")!)
        request.timeoutInterval = 25
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("StarDash/\(Self.version)", forHTTPHeaderField: "User-Agent")
        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            let result: Result<PublishedRelease?, Error> = Result {
                if let error { throw error }
                guard let http = response as? HTTPURLResponse else { throw dashError("更新服务没有返回有效响应。") }
                if http.statusCode == 404 { return nil }
                guard http.statusCode == 200, let data else { throw dashError("更新检查失败（HTTP \(http.statusCode)）。") }
                return try JSONDecoder().decode(PublishedRelease.self, from: data)
            }
            DispatchQueue.main.async {
                guard let self else { return }
                self.busy = false
                do {
                    if let release = try result.get() {
                        let available = try release.newer(than: Self.version)
                        self.latestVersion = release.tag_name
                        self.updateState = available ? "available" : "current"
                        self.message = available ? "发现 \(release.tag_name)，可通过 Homebrew 更新并重启。" : "当前已是最新版本。"
                    } else {
                        self.latestVersion = nil
                        self.updateState = "unpublished"
                        self.message = "尚未发布正式版本，暂时无法在线更新。"
                    }
                } catch {
                    self.updateState = "failed"
                    self.showError(error)
                }
            }
        }.resume()
    }

    func updateAndRestart() throws {
        guard !busy else { throw dashError("正在检查或安装更新，请稍后再试。") }
        guard let brew = HomebrewUpdate.executable else { throw dashError("未找到 Homebrew；请先安装 Homebrew 和星盘的 Cask。") }
        let app = Bundle.main.bundleURL.resolvingSymlinksInPath()
        let allowed = [URL(fileURLWithPath: "/Applications/StarDash.app"),
                       FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications/StarDash.app")]
        guard allowed.contains(app) else { throw dashError("请从 Homebrew 安装的 Applications/StarDash.app 执行更新。") }
        let manager = FileManager.default
        try manager.createDirectory(at: logURL.deletingLastPathComponent(), withIntermediateDirectories: true,
                                    attributes: [.posixPermissions: 0o700])
        try Data().write(to: logURL, options: .atomic)
        try manager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: logURL.path)
        let log = try FileHandle(forWritingTo: logURL)
        let originalVersion = Self.version
        busy = true
        updateState = "installing"
        message = "正在通过 Homebrew 更新，完成后将自动重启…"
        DispatchQueue.global(qos: .utility).async { [weak self] in
            defer { try? log.close() }
            let result = Result {
                _ = try HomebrewUpdate.installedVersion(HomebrewUpdate.run(brew, ["info", "--json=v2", "--cask", HomebrewUpdate.cask]))
                _ = try HomebrewUpdate.run(brew, ["update"], log: log)
                _ = try HomebrewUpdate.run(brew, ["upgrade", "--cask", HomebrewUpdate.cask], log: log)
                let plist = try PropertyListSerialization.propertyList(from: Data(contentsOf: app.appendingPathComponent("Contents/Info.plist")), format: nil) as? [String: Any]
                guard plist?["CFBundleIdentifier"] as? String == "tech.stardream.StarDash",
                      let installed = plist?["CFBundleShortVersionString"] as? String,
                      let version = ReleaseVersion(installed), let current = ReleaseVersion(originalVersion), version >= current else {
                    throw dashError("升级后应用校验失败，未重启当前进程。")
                }
                return installed
            }
            DispatchQueue.main.async {
                guard let self else { return }
                self.busy = false
                do {
                    let installed = try result.get()
                    if let latest = self.latestVersion, let published = ReleaseVersion(latest),
                       let local = ReleaseVersion(installed), local < published {
                        throw dashError("Homebrew 尚未同步 \(latest)，当前应用保持运行。")
                    }
                    try self.restart()
                } catch {
                    self.updateState = "failed"
                    self.showError(error)
                }
            }
        }
    }

    func restart() throws {
        guard !busy else { throw dashError("正在更新，请等待更新完成再重启。") }
        let app = Bundle.main.bundleURL
        guard app.pathExtension == "app", FileManager.default.fileExists(atPath: app.appendingPathComponent("Contents/MacOS/StarDash").path) else {
            throw dashError("请从 StarDash.app 重启应用。")
        }
        // The helper waits for the old process to exit before opening the same app bundle.
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-f", "-c", "for i in {1..100}; do /bin/kill -0 \"$1\" 2>/dev/null || exec /usr/bin/open -g -n \"$2\" --args --background; /bin/sleep 0.1; done; exit 1", "stardash-restart", String(ProcessInfo.processInfo.processIdentifier), app.path]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        updateState = "restarting"
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { NSApp.terminate(nil) }
    }
}
