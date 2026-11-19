import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate, NSWindowDelegate {
    private let model = AppModel()
    private var statusItem: NSStatusItem!
    private let popover = NSPopover()
    private var panel: NSPanel?
    private var commandEditor: NSWindow?
    private var popupHost: NSHostingController<DashboardView>?
    private var panelHost: NSHostingController<DashboardView>?
    private var floating = false
    private var control: LocalControl?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        let control = LocalControl { [weak self] arguments in
            guard let self else { throw dashError("星盘正在退出。") }
            return try self.handleControl(arguments)
        }
        do { try control.start(); self.control = control }
        catch { fputs("StarDash: \(error.localizedDescription)\n", stderr); NSApp.terminate(nil); return }
        createMenu()
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "sparkles", accessibilityDescription: "星盘")
            button.toolTip = "星盘 · 电脑状态"
            button.target = self
            button.action = #selector(togglePanel)
        }
        popover.behavior = .transient
        popover.animates = false
        popover.delegate = self
        popupHost = NSHostingController(rootView: dashboard(floating: false))
        popover.contentViewController = popupHost
        resizeViews()
        model.setVisible(false)
        if !CommandLine.arguments.contains("--background") &&
            (CommandLine.arguments.contains("--show-window") || UserDefaults.standard.bool(forKey: "preferFloating")) {
            showFloating()
        } else {
            floating = UserDefaults.standard.bool(forKey: "preferFloating")
        }
    }

    private func settings() -> [String: Bool] {
        ["compact": model.compact, "pinned": model.pinned, "showCPU": model.showCPU,
         "showMemory": model.showMemory, "showNetwork": model.showNetwork, "showBattery": model.showBattery]
    }

    private func handleControl(_ args: [String]) throws -> [String: Any] {
        try DashCLI.validate(args)
        switch args[0] {
        case "status":
            model.lifecycle.refreshLoginStatus()
            return ["running": true, "version": AppLifecycle.version, "pid": ProcessInfo.processInfo.processIdentifier,
                    "metrics": try ControlJSON.object(model.snapshot), "settings": settings(),
                    "mode": floating ? "floating" : "panel", "commands_count": model.commands.count,
                    "command_message": model.commandMessage as Any? ?? NSNull(),
                    "awake": ["active": model.awake.isActive, "remaining_seconds": model.awake.remaining],
                    "startup": model.lifecycle.loginStatus,
                    "update": ["state": model.lifecycle.updateState, "latest_version": model.lifecycle.latestVersion as Any? ?? NSNull(),
                               "message": model.lifecycle.message as Any? ?? NSNull(), "log_path": model.lifecycle.logURL.path]]
        case "show":
            if args.last == "floating" || (args.count == 1 && floating) { showFloating() }
            else {
                panel?.orderOut(nil)
                floating = false
                UserDefaults.standard.set(false, forKey: "preferFloating")
                showPopover()
            }
            return ["mode": floating ? "floating" : "panel"]
        case "settings":
            if args[1] == "set" {
                let value = args[3] == "true"
                switch args[2] {
                case "compact": model.compact = value
                case "pinned": model.pinned = value; panel?.level = value ? .floating : .normal
                case "showCPU": model.showCPU = value
                case "showMemory": model.showMemory = value
                case "showNetwork": model.showNetwork = value
                case "showBattery": model.showBattery = value
                default: break
                }
                resizeViews()
            }
            return ["settings": settings()]
        case "awake":
            if args[1] == "stop" { model.awake.stop() }
            else {
                guard !model.awake.isActive else { throw dashError("防休眠已在运行，请先结束。") }
                model.awake.start(seconds: TimeInterval(Int(args[3])! * 60))
            }
            if let message = model.awake.message { throw dashError(message) }
            return ["active": model.awake.isActive, "remaining_seconds": model.awake.remaining]
        case "commands":
            if args[1] == "list" { return ["commands": try ControlJSON.object(model.commands)] }
            if args[1] == "add" {
                let values = try DashCLI.options(Array(args.dropFirst(2)), allowed: ["--name", "--command", "--icon"])
                let command = try CommandShortcut(name: values["--name"]!, command: values["--command"]!, icon: values["--icon"] ?? "terminal.fill")
                try model.saveCommand(command)
                return ["command": try ControlJSON.object(command)]
            }
            guard let command = model.commands.first(where: { $0.id.uuidString.lowercased() == args[2].lowercased() }) else {
                throw dashError("找不到这个命令 UUID。")
            }
            if args[1] == "remove" { try model.deleteCommand(command); return ["removed": command.id.uuidString] }
            if args[1] == "run" {
                model.runCommand(command)
                return ["accepted": true, "command_id": command.id.uuidString, "message": "已请求终端执行，请在终端查看结果。"]
            }
            let values = try DashCLI.options(Array(args.dropFirst(3)), allowed: ["--name", "--command", "--icon"])
            let edited = try CommandShortcut(id: command.id, name: values["--name"] ?? command.name,
                                             command: values["--command"] ?? command.command, icon: values["--icon"] ?? command.icon)
            try model.saveCommand(edited)
            return ["command": try ControlJSON.object(edited)]
        case "startup":
            if args[1] != "status" { try model.lifecycle.setStartAtLogin(args[1] == "enable") }
            model.lifecycle.refreshLoginStatus()
            return ["startup": model.lifecycle.loginStatus, "message": model.lifecycle.message as Any? ?? NSNull()]
        case "update":
            if args[1] == "check" { try model.lifecycle.checkForUpdates() }
            else { try model.lifecycle.updateAndRestart() }
            return ["accepted": true, "state": model.lifecycle.updateState, "message": model.lifecycle.message as Any? ?? NSNull()]
        case "restart":
            try model.lifecycle.restart()
            return ["accepted": true, "state": "restarting"]
        case "quit":
            guard !model.lifecycle.busy else { throw dashError("正在检查或安装更新，请稍后退出。") }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { NSApp.terminate(nil) }
            return ["accepted": true, "state": "quitting"]
        default: throw dashError("未知命令。")
        }
    }

    private func dashboard(floating: Bool) -> DashboardView {
        DashboardView(model: model, floating: floating,
                      switchMode: { [weak self] in self?.switchMode() },
                      resize: { [weak self] in self?.resizeViews() },
                      setPinned: { [weak self] in self?.panel?.level = self?.model.pinned == true ? .floating : .normal },
                      quit: { NSApp.terminate(nil) },
                      editCommand: { [weak self] command in self?.showCommandEditor(command) })
    }

    private func showCommandEditor(_ command: CommandShortcut?) {
        popover.performClose(nil)
        if commandEditor == nil {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 430, height: 420),
                                  styleMask: [.titled, .closable], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.center()
            commandEditor = window
        }
        guard let window = commandEditor else { return }
        window.title = command == nil ? "星盘 · 添加命令" : "星盘 · 编辑命令"
        window.contentViewController = NSHostingController(rootView: CommandEditorView(model: model, original: command) {
            window.orderOut(nil)
        })
        window.setContentSize(window.contentViewController!.view.fittingSize)
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    private func createMenu() {
        let menu = NSMenu()
        let root = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "退出星盘", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        root.submenu = appMenu
        menu.addItem(root)
        NSApp.mainMenu = menu
    }

    @objc private func togglePanel() {
        if floating {
            if panel?.isVisible == true {
                panel?.orderOut(nil)
                model.setVisible(false)
            } else {
                showFloating()
            }
        } else if popover.isShown {
            popover.performClose(nil)
        } else {
            showPopover()
        }
    }

    private func showPopover() {
        guard let button = statusItem.button else { return }
        resizeViews()
        NSApp.activate(ignoringOtherApps: true)
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
    }

    private func showFloating() {
        popover.performClose(nil)
        floating = true
        UserDefaults.standard.set(true, forKey: "preferFloating")
        if panel == nil {
            let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 372, height: 440),
                                styleMask: [.titled, .closable], backing: .buffered, defer: false)
            panel.title = "星盘 · 悬浮窗口"
            panel.identifier = NSUserInterfaceItemIdentifier("StarDashFloating")
            panel.hidesOnDeactivate = false
            panel.isReleasedWhenClosed = false
            panel.isMovableByWindowBackground = true
            panel.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
            panel.delegate = self
            panelHost = NSHostingController(rootView: dashboard(floating: true))
            panel.contentViewController = panelHost
            panel.center()
            panel.setFrameAutosaveName("StarDashFloating")
            self.panel = panel
        }
        panel?.level = model.pinned ? .floating : .normal
        resizeViews()
        panel?.makeKeyAndOrderFront(nil)
        model.setVisible(true)
    }

    private func switchMode() {
        if floating {
            panel?.orderOut(nil)
            floating = false
            UserDefaults.standard.set(false, forKey: "preferFloating")
            showPopover()
        } else {
            showFloating()
        }
    }

    private func resizeViews() {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            if let host = self.popupHost {
                host.view.layoutSubtreeIfNeeded()
                self.popover.contentSize = host.view.fittingSize
            }
            if let host = self.panelHost, let panel = self.panel {
                host.view.layoutSubtreeIfNeeded()
                let size = host.view.fittingSize
                let top = panel.frame.maxY
                panel.setContentSize(size)
                var origin = panel.frame.origin
                origin.y = top - panel.frame.height
                panel.setFrameOrigin(origin)
                self.keepOnScreen(panel)
            }
        }
    }

    private func keepOnScreen(_ panel: NSPanel) {
        guard let screen = panel.screen ?? NSScreen.main else { return }
        let bounds = screen.visibleFrame
        var frame = panel.frame
        frame.origin.x = min(max(bounds.minX, frame.minX), max(bounds.minX, bounds.maxX - frame.width))
        frame.origin.y = min(max(bounds.minY, frame.minY), max(bounds.minY, bounds.maxY - frame.height))
        panel.setFrameOrigin(frame.origin)
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        sender.orderOut(nil)
        model.setVisible(false)
        return false
    }

    func popoverDidShow(_ notification: Notification) { model.setVisible(true) }
    func popoverDidClose(_ notification: Notification) { model.setVisible(floating && panel?.isVisible == true) }

    func applicationDidChangeScreenParameters(_ notification: Notification) {
        if let panel, panel.isVisible { keepOnScreen(panel) }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if floating { showFloating() } else { showPopover() }
        return true
    }

    func applicationWillBecomeActive(_ notification: Notification) { model.lifecycle.refreshLoginStatus() }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        if model.lifecycle.busy {
            model.lifecycle.showError(dashError("正在检查或安装更新，请稍后退出。"))
            return .terminateCancel
        }
        return .terminateNow
    }

    func applicationWillTerminate(_ notification: Notification) { control?.stop(); model.shutdown() }
}

do {
    if CommandLine.arguments.dropFirst().first == "--cli" {
        exit(try DashCLI.run(Array(CommandLine.arguments.dropFirst(2))))
    }
    if CommandLine.arguments.contains("--self-test") {
        try SelfTests.run()
        exit(0)
    }
    if CommandLine.arguments.contains("--power-test") {
        try SelfTests.power()
        exit(0)
    }
    if CommandLine.arguments.contains("--diagnostics") {
        let sampler = MetricsSampler()
        _ = sampler.sample()
        Thread.sleep(forTimeInterval: 1)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        print(String(decoding: try encoder.encode(sampler.sample()), as: UTF8.self))
        exit(0)
    }
} catch {
    if CommandLine.arguments.dropFirst().first == "--cli" {
        print(String(decoding: ControlJSON.data(["ok": false, "error": error.localizedDescription]), as: UTF8.self))
        exit(1)
    }
    fputs("StarDash: \(error.localizedDescription)\n", stderr)
    exit(1)
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
