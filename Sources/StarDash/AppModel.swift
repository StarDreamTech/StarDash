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
    let awake = KeepAwake()
    private let defaults: UserDefaults
    private let sampler = MetricsSampler()
    private let queue = DispatchQueue(label: "StarDash.metrics", qos: .utility)
    private var timer: Timer?
    private var collecting = false

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
