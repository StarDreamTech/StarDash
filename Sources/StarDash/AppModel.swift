import Foundation
import Combine

final class AppModel: ObservableObject {
    @Published private(set) var snapshot = MetricsSnapshot()
    @Published var compact: Bool { didSet { defaults.set(compact, forKey: "compact") } }
    @Published var pinned: Bool { didSet { defaults.set(pinned, forKey: "pinned") } }
    @Published var showCPU: Bool { didSet { defaults.set(showCPU, forKey: "showCPU") } }
    @Published var showMemory: Bool { didSet { defaults.set(showMemory, forKey: "showMemory") } }
    @Published var showNetwork: Bool { didSet { defaults.set(showNetwork, forKey: "showNetwork") } }
    @Published var showBattery: Bool { didSet { defaults.set(showBattery, forKey: "showBattery") } }
    @Published var minutes: Int { didSet { defaults.set(minutes, forKey: "minutes") } }
    @Published private(set) var commands: [CommandShortcut]
    @Published private(set) var commandMessage: String?
    let awake = KeepAwake()
    private let defaults: UserDefaults
    private let sampler = MetricsSampler()
    private let queue = DispatchQueue(label: "StarDash.metrics", qos: .utility)
    private var timer: Timer?
    private var collecting = false
    private var commandsLoadFailed = false

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        defaults.register(defaults: ["compact": false, "pinned": false, "showCPU": true,
                                     "showMemory": true, "showNetwork": true, "showBattery": true, "minutes": 30])
        compact = defaults.bool(forKey: "compact")
        pinned = defaults.bool(forKey: "pinned")
        showCPU = defaults.bool(forKey: "showCPU")
        showMemory = defaults.bool(forKey: "showMemory")
        showNetwork = defaults.bool(forKey: "showNetwork")
        showBattery = defaults.bool(forKey: "showBattery")
        let saved = defaults.integer(forKey: "minutes")
        minutes = [15, 30, 60, 120].contains(saved) ? saved : 30
        if let data = defaults.data(forKey: "commands") {
            do {
                commands = try JSONDecoder().decode([CommandShortcut].self, from: data)
                    .map { try CommandShortcut(id: $0.id, name: $0.name, command: $0.command, icon: $0.icon) }
            } catch {
                commands = []
                commandsLoadFailed = true
                commandMessage = "已保存的命令无法读取，原数据已保留。"
            }
        } else {
            commands = []
        }
    }

    func saveCommand(_ command: CommandShortcut) throws {
        var updated = commands
        if let index = updated.firstIndex(where: { $0.id == command.id }) { updated[index] = command }
        else { updated.append(command) }
        try storeCommands(updated)
    }

    func deleteCommand(_ command: CommandShortcut) throws {
        try storeCommands(commands.filter { $0.id != command.id })
    }

    private func storeCommands(_ updated: [CommandShortcut]) throws {
        // Preserve unreadable data instead of silently replacing a user's saved commands.
        if commandsLoadFailed {
            throw NSError(domain: "StarDash.Command", code: 3,
                          userInfo: [NSLocalizedDescriptionKey: "已保存的命令数据损坏，请先备份并修复后再保存。"])
        }
        let data = try JSONEncoder().encode(updated)
        defaults.set(data, forKey: "commands")
        commands = updated
        commandMessage = nil
    }

    func runCommand(_ command: CommandShortcut) {
        commandMessage = nil
        TerminalCommand.run(command) { [weak self] error in self?.commandMessage = error }
    }

    func setVisible(_ visible: Bool) {
        timer?.invalidate()
        collect()
        let timer = Timer(timeInterval: visible ? 2 : 10, repeats: true) { [weak self] _ in self?.collect() }
        timer.tolerance = visible ? 0.2 : 2
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func collect() {
        guard !collecting else { return }
        collecting = true
        queue.async { [weak self] in
            guard let self else { return }
            let value = self.sampler.sample()
            DispatchQueue.main.async { [weak self] in
                self?.snapshot = value
                self?.collecting = false
            }
        }
    }

    func shutdown() {
        timer?.invalidate()
        awake.stop()
    }
}
