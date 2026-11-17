import Foundation
import Combine
import IOKit.pwr_mgt

final class KeepAwake: ObservableObject {
    @Published private(set) var deadline: Date?
    @Published private(set) var remaining: TimeInterval = 0
    @Published private(set) var message: String?
    private var assertion: IOPMAssertionID?
    private var timer: Timer?
    var isActive: Bool { assertion != nil }

    func start(seconds: TimeInterval) {
        guard assertion == nil else { return }
        guard seconds.isFinite, seconds > 0, seconds <= 86_400 else {
            message = "请选择有效的持续时间"
            return
        }
        var id: IOPMAssertionID = 0
        let status = IOPMAssertionCreateWithDescription(
            kIOPMAssertionTypePreventUserIdleSystemSleep as CFString,
            "StarDash timed keep-awake" as CFString, nil, nil, nil,
            seconds, kIOPMAssertionTimeoutActionTurnOff as CFString, &id)
        guard status == kIOReturnSuccess else {
            message = "未能开启防休眠（\(status)），请稍后重试"
            return
        }
        assertion = id
        deadline = Date().addingTimeInterval(seconds)
        remaining = seconds
        message = nil
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in self?.tick() }
        timer.tolerance = 0.1
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func stop() {
        guard let assertion else { return }
        let status = IOPMAssertionRelease(assertion)
        guard status == kIOReturnSuccess else {
            message = "未能确认结束状态（\(status)），可退出星盘释放"
            return
        }
        self.assertion = nil
        timer?.invalidate()
        timer = nil
        deadline = nil
        remaining = 0
        message = nil
    }

    private func tick() {
        guard let deadline else { return }
        remaining = max(0, deadline.timeIntervalSinceNow)
        if remaining <= 0 { stop() }
    }

    deinit {
        timer?.invalidate()
        if let assertion { IOPMAssertionRelease(assertion) }
    }
}
