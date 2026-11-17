import Foundation
import Darwin
import IOKit.ps

struct CPUTicks {
    let values: [UInt32]

    func usage(since previous: CPUTicks) -> Double? {
        guard values.count == 4, previous.values.count == 4 else { return nil }
        let deltas = zip(values, previous.values).map { UInt64($0 &- $1) }
        let total = deltas.reduce(0, +)
        guard total > 0 else { return nil }
        return 100 * Double(total - deltas[Int(CPU_STATE_IDLE)]) / Double(total)
    }
}

struct MemoryReading: Codable {
    let used: UInt64
    let total: UInt64
    var fraction: Double { total > 0 ? Double(used) / Double(total) : 0 }
}

struct NetworkCounter {
    let received: UInt64
    let sent: UInt64
}

struct NetworkRate: Codable {
    let download: Double
    let upload: Double

    static func between(_ previous: [UInt16: NetworkCounter],
                        _ current: [UInt16: NetworkCounter], seconds: Double) -> NetworkRate? {
        guard seconds > 0, seconds.isFinite else { return nil }
        var received: UInt64 = 0
        var sent: UInt64 = 0
        for (index, value) in current {
            guard let old = previous[index] else { continue }
            if value.received >= old.received { received += value.received - old.received }
            if value.sent >= old.sent { sent += value.sent - old.sent }
        }
        return NetworkRate(download: Double(received) / seconds, upload: Double(sent) / seconds)
    }
}

struct BatteryReading: Codable {
    // nil means the source could not be read; false means there is no internal battery.
    let present: Bool?
    let percentage: Int?
    let state: String
}

struct MetricsSnapshot: Codable {
    var capturedAt = Date()
    var cpuPercent: Double?
    var memory: MemoryReading?
    var network: NetworkRate?
    var battery = BatteryReading(present: nil, percentage: nil, state: "采集中")
    var errors: [String: String] = [:]
}

final class MetricsSampler {
    private var previousCPU: CPUTicks?
    private var previousNetwork: (time: TimeInterval, counters: [UInt16: NetworkCounter])?

    func sample() -> MetricsSnapshot {
        var result = MetricsSnapshot()
        let host = mach_host_self()
        defer { mach_port_deallocate(mach_task_self_, host) }
        if let cpu = readCPU(host) {
            result.cpuPercent = previousCPU.flatMap { cpu.usage(since: $0) }
            previousCPU = cpu
        } else {
            previousCPU = nil
            result.errors["cpu"] = "暂时无法读取处理器状态"
        }
        result.memory = readMemory(host)
        if result.memory == nil { result.errors["memory"] = "暂时无法读取内存状态" }
        let now = ProcessInfo.processInfo.systemUptime
        if let counters = readNetwork() {
            if let old = previousNetwork {
                result.network = NetworkRate.between(old.counters, counters, seconds: now - old.time)
            }
            previousNetwork = (now, counters)
        } else {
            previousNetwork = nil
            result.errors["network"] = "暂时无法读取网络统计"
        }
        result.battery = readBattery()
        if result.battery.present == nil || (result.battery.present == true && result.battery.percentage == nil) {
            result.errors["battery"] = "暂时无法读取电池电量"
        }
        return result
    }

    private func readCPU(_ host: host_t) -> CPUTicks? {
        var info = host_cpu_load_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout.size(ofValue: info) / MemoryLayout<integer_t>.size)
        let status = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics(host, HOST_CPU_LOAD_INFO, $0, &count)
            }
        }
        guard status == KERN_SUCCESS else { return nil }
        let ticks = info.cpu_ticks
        return CPUTicks(values: [ticks.0, ticks.1, ticks.2, ticks.3])
    }

    private func readMemory(_ host: host_t) -> MemoryReading? {
        var info = vm_statistics64_data_t()
        var count = mach_msg_type_number_t(MemoryLayout.size(ofValue: info) / MemoryLayout<integer_t>.size)
        let status = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(host, HOST_VM_INFO64, $0, &count)
            }
        }
        var pageSize: vm_size_t = 0
        guard status == KERN_SUCCESS, host_page_size(host, &pageSize) == KERN_SUCCESS else { return nil }
        let occupied = UInt64(info.active_count) + UInt64(info.inactive_count)
            + UInt64(info.wire_count) + UInt64(info.compressor_page_count)
        let reclaimable = UInt64(info.purgeable_count) + UInt64(info.external_page_count)
        let total = ProcessInfo.processInfo.physicalMemory
        let used = min(total, (occupied > reclaimable ? occupied - reclaimable : 0) * UInt64(pageSize))
        return MemoryReading(used: used, total: total)
    }

    private func readNetwork() -> [UInt16: NetworkCounter]? {
        var mib: [Int32] = [CTL_NET, PF_ROUTE, 0, 0, NET_RT_IFLIST2, 0]
        for _ in 0..<3 {
            var size = 0
            guard sysctl(&mib, 6, nil, &size, nil, 0) == 0 else { return nil }
            var bytes = [UInt8](repeating: 0, count: size)
            let status = bytes.withUnsafeMutableBytes { sysctl(&mib, 6, $0.baseAddress, &size, nil, 0) }
            if status != 0 {
                if errno == ENOMEM { continue }
                return nil
            }
            return bytes.withUnsafeBytes { raw in
                var offset = 0
                var counters: [UInt16: NetworkCounter] = [:]
                while offset + 4 <= size {
                    let length = Int(raw.loadUnaligned(fromByteOffset: offset, as: UInt16.self))
                    guard length >= 4, offset + length <= size else { return nil }
                    if raw[offset + 3] == UInt8(RTM_IFINFO2), length >= MemoryLayout<if_msghdr2>.size {
                        let info = raw.loadUnaligned(fromByteOffset: offset, as: if_msghdr2.self)
                        var name = [CChar](repeating: 0, count: Int(IFNAMSIZ))
                        if_indextoname(UInt32(info.ifm_index), &name)
                        // Count physical Ethernet/Wi-Fi once; VPN and bridge counters would duplicate traffic.
                        if String(cString: name).hasPrefix("en"), info.ifm_data.ifi_type == IFT_ETHER,
                           info.ifm_flags & IFF_UP != 0, info.ifm_flags & IFF_RUNNING != 0 {
                            counters[info.ifm_index] = NetworkCounter(received: info.ifm_data.ifi_ibytes,
                                                                    sent: info.ifm_data.ifi_obytes)
                        }
                    }
                    offset += length
                }
                return counters
            }
        }
        return nil
    }

    private func readBattery() -> BatteryReading {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef] else {
            return BatteryReading(present: nil, percentage: nil, state: "不可用")
        }
        for source in sources {
            guard let description = IOPSGetPowerSourceDescription(info, source)?.takeUnretainedValue() as? [String: Any],
                  description[kIOPSTypeKey] as? String == kIOPSInternalBatteryType,
                  description[kIOPSIsPresentKey] as? Bool != false else { continue }
            let current = description[kIOPSCurrentCapacityKey] as? Int
            let maximum = description[kIOPSMaxCapacityKey] as? Int
            let percentage = current.flatMap { value in maximum.flatMap { $0 > 0 ? min(100, max(0, value * 100 / $0)) : nil } }
            let charging = description[kIOPSIsChargingKey] as? Bool == true
            let plugged = description[kIOPSPowerSourceStateKey] as? String == kIOPSACPowerValue
            let state = charging ? "正在充电" : (plugged ? "已接电" : "使用电池")
            return BatteryReading(present: true, percentage: percentage, state: state)
        }
        return BatteryReading(present: false, percentage: nil, state: "无内置电池")
    }
}

enum MetricText {
    static func bytes(_ value: UInt64) -> String {
        let gb = Double(value) / 1_073_741_824
        return gb >= 1 ? String(format: "%.1f GB", gb) : String(format: "%.0f MB", Double(value) / 1_048_576)
    }

    static func rate(_ bytes: Double) -> String {
        guard bytes.isFinite, bytes >= 0 else { return "不可用" }
        if bytes >= 1_000_000 { return String(format: "%.1f MB/s", bytes / 1_000_000) }
        if bytes >= 1_000 { return String(format: "%.1f KB/s", bytes / 1_000) }
        return String(format: "%.0f B/s", bytes)
    }

    static func countdown(_ seconds: TimeInterval) -> String {
        let value = max(0, Int(ceil(seconds)))
        return String(format: "%02d:%02d:%02d", value / 3600, value / 60 % 60, value % 60)
    }
}
