import AppKit

struct CommandShortcut: Codable, Identifiable, Equatable {
    let id: UUID
    var name: String
    var command: String
    var icon: String

    static let icons = ["terminal.fill", "bolt.fill", "hammer.fill", "folder.fill", "network", "arrow.clockwise"]

    init(id: UUID = UUID(), name: String, command: String, icon: String = "terminal.fill") throws {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, !command.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw NSError(domain: "StarDash.Command", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "请填写名称和命令。"])
        }
        guard !command.contains("\0") else {
            throw NSError(domain: "StarDash.Command", code: 2,
                          userInfo: [NSLocalizedDescriptionKey: "命令不能包含空字符。"])
        }
        self.id = id
        self.name = name
        self.command = command
        self.icon = Self.icons.contains(icon) ? icon : Self.icons[0]
    }
}

enum TerminalCommand {
    static func shellQuote(_ text: String) -> String {
        "'" + text.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    static func script(for shortcut: CommandShortcut, home: URL) -> String {
        """
        #!/bin/zsh
        /bin/rm -f -- "$0"
        /bin/rmdir -- "${0:h}" 2>/dev/null
        cd -- \(shellQuote(home.path)) || exit 1
        exec /bin/zsh -lic \(shellQuote(shortcut.command))

        """
    }

    static func prepare(_ shortcut: CommandShortcut) throws -> URL {
        let manager = FileManager.default
        let directory = manager.temporaryDirectory.appendingPathComponent("StarDash-\(UUID().uuidString)", isDirectory: true)
        try manager.createDirectory(at: directory, withIntermediateDirectories: false,
                                    attributes: [.posixPermissions: 0o700])
        do {
            let file = directory.appendingPathComponent("运行命令.command")
            try Data(script(for: shortcut, home: manager.homeDirectoryForCurrentUser).utf8)
                .write(to: file, options: .withoutOverwriting)
            try manager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: file.path)
            return file
        } catch {
            try? manager.removeItem(at: directory)
            throw error
        }
    }

    static func run(_ shortcut: CommandShortcut, completion: @escaping (String?) -> Void) {
        do {
            guard let terminal = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.Terminal") else {
                completion("找不到系统终端。")
                return
            }
            let file = try prepare(shortcut)
            NSWorkspace.shared.open([file], withApplicationAt: terminal, configuration: .init()) { _, error in
                if error != nil { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
                DispatchQueue.main.async { completion(error.map { "无法打开终端：\($0.localizedDescription)" }) }
            }
        } catch {
            completion("无法准备命令：\(error.localizedDescription)")
        }
    }
}
