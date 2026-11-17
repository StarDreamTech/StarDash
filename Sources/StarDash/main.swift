import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate, NSWindowDelegate {
    private let model = AppModel()
    private var statusItem: NSStatusItem!
    private let popover = NSPopover()
    private var panel: NSPanel?
    private var popupHost: NSHostingController<DashboardView>?
    private var panelHost: NSHostingController<DashboardView>?
    private var floating = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
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
        if CommandLine.arguments.contains("--show-window") || UserDefaults.standard.bool(forKey: "preferFloating") {
            showFloating()
        }
    }

    private func dashboard(floating: Bool) -> DashboardView {
        DashboardView(model: model, floating: floating,
                      switchMode: { [weak self] in self?.switchMode() },
                      resize: { [weak self] in self?.resizeViews() },
                      setPinned: { [weak self] in self?.panel?.level = self?.model.pinned == true ? .floating : .normal },
                      quit: { NSApp.terminate(nil) })
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
                panel?.makeKeyAndOrderFront(nil)
                model.setVisible(true)
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

    func applicationWillTerminate(_ notification: Notification) { model.shutdown() }
}

do {
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
    fputs("StarDash: \(error.localizedDescription)\n", stderr)
    exit(1)
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
