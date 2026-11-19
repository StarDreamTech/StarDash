import SwiftUI
import ServiceManagement

struct DashboardView: View {
    @ObservedObject var model: AppModel
    let floating: Bool
    let switchMode: () -> Void
    let resize: () -> Void
    let setPinned: () -> Void
    let quit: () -> Void
    let editCommand: (CommandShortcut?) -> Void
    private let columns = [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 9) {
                Image(systemName: "sparkles").font(.title2).foregroundStyle(.indigo)
                VStack(alignment: .leading, spacing: 1) {
                    Text("星盘").font(.headline)
                    Text("电脑状态，一眼即知").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                if floating {
                    Button { model.pinned.toggle(); setPinned() } label: {
                        Image(systemName: model.pinned ? "pin.fill" : "pin")
                    }
                    .help(model.pinned ? "取消置顶" : "置顶悬浮窗口")
                    .accessibilityLabel(model.pinned ? "取消置顶" : "置顶悬浮窗口")
                }
                Button(action: switchMode) {
                    Image(systemName: floating ? "menubar.rectangle" : "rectangle.on.rectangle")
                }
                .help(floating ? "回到菜单栏面板" : "切换为悬浮窗口")
                .accessibilityLabel(floating ? "回到菜单栏面板" : "切换为悬浮窗口")
            }
            .buttonStyle(.borderless)

            LazyVGrid(columns: columns, spacing: 10) {
                if model.showCPU {
                    MetricCard(title: "CPU", icon: "cpu", color: .indigo,
                               value: model.snapshot.cpuPercent.map { String(format: "%.1f%%", $0) } ?? placeholder("cpu"),
                               detail: "处理器使用率", fraction: model.snapshot.cpuPercent.map { $0 / 100 }, compact: model.compact)
                    .help(model.snapshot.errors["cpu"] ?? "所有处理器核心的综合负载")
                }
                if model.showMemory {
                    MetricCard(title: "内存", icon: "memorychip", color: .purple,
                               value: model.snapshot.memory.map { MetricText.bytes($0.used) } ?? placeholder("memory"),
                               detail: model.snapshot.memory.map { "共 \(MetricText.bytes($0.total)) · \(Int($0.fraction * 100))%" } ?? "正在读取",
                               fraction: model.snapshot.memory?.fraction, compact: model.compact)
                    .help(model.snapshot.errors["memory"] ?? "已用内存估算，扣除可回收缓存；可能与活动监视器略有差异")
                }
                if model.showNetwork {
                    MetricCard(title: "网速", icon: "arrow.up.arrow.down", color: .teal,
                               value: model.snapshot.network.map { "↓ \(MetricText.rate($0.download))" } ?? placeholder("network"),
                               detail: model.snapshot.network.map { "↑ \(MetricText.rate($0.upload))" } ?? "首次采样中",
                               fraction: nil, compact: model.compact)
                    .help(model.snapshot.errors["network"] ?? "Wi-Fi 与以太网实际流量，不重复计入 VPN 虚拟接口")
                }
                if model.showBattery, model.snapshot.battery.present != false {
                    MetricCard(title: "电池", icon: "battery.75percent", color: .green,
                               value: model.snapshot.battery.percentage.map { "\($0)%" } ?? placeholder("battery"),
                               detail: model.snapshot.battery.state,
                               fraction: model.snapshot.battery.percentage.map { Double($0) / 100 }, compact: model.compact)
                    .help(model.snapshot.errors["battery"] ?? "内置电池电量与供电状态")
                }
            }
            if !model.showCPU && !model.showMemory && !model.showNetwork
                && (!model.showBattery || model.snapshot.battery.present == false) {
                Text("在“显示项目”中选择要查看的状态")
                    .font(.callout).foregroundStyle(.secondary).frame(maxWidth: .infinity).padding(.vertical, 12)
            }
            if !model.compact {
                AwakeView(awake: model.awake, minutes: $model.minutes)
            } else {
                AwakeSummary(awake: model.awake)
            }
            CommandShortcutsView(model: model, edit: editCommand)
            HStack {
                Menu {
                    Toggle("CPU", isOn: $model.showCPU)
                    Toggle("内存", isOn: $model.showMemory)
                    Toggle("网速", isOn: $model.showNetwork)
                    Toggle("电池", isOn: $model.showBattery)
                } label: { Label("显示项目", systemImage: "slider.horizontal.3") }
                .menuStyle(.borderlessButton).fixedSize()
                Spacer()
                Button { model.compact.toggle() } label: {
                    Label(model.compact ? "展开" : "精简", systemImage: model.compact ? "chevron.down" : "chevron.up")
                }
                .accessibilityLabel(model.compact ? "展开面板" : "精简面板")
                Menu {
                    LifecycleMenu(lifecycle: model.lifecycle, quit: quit)
                } label: { Image(systemName: "ellipsis.circle") }
                .menuStyle(.borderlessButton).fixedSize().accessibilityLabel("更多")
            }
            .font(.caption).foregroundStyle(.secondary).buttonStyle(.borderless)
            LifecycleMessage(lifecycle: model.lifecycle)
        }
        .padding(18)
        .frame(width: 372)
        .fixedSize(horizontal: true, vertical: true)
        .background(.regularMaterial)
        .onChange(of: model.compact) { _ in resize() }
        .onChange(of: model.showCPU) { _ in resize() }
        .onChange(of: model.showMemory) { _ in resize() }
        .onChange(of: model.showNetwork) { _ in resize() }
        .onChange(of: model.showBattery) { _ in resize() }
        .onChange(of: model.snapshot.battery.present) { _ in resize() }
        .onReceive(model.awake.$message) { _ in resize() }
        .onReceive(model.awake.$deadline) { _ in resize() }
        .onChange(of: model.commands.count) { _ in resize() }
        .onChange(of: model.commandMessage) { _ in resize() }
        .onReceive(model.lifecycle.$message) { _ in resize() }
    }

    private func placeholder(_ key: String) -> String {
        model.snapshot.errors[key] == nil ? "采集中" : "不可用"
    }
}

private struct LifecycleMenu: View {
    @ObservedObject var lifecycle: AppLifecycle
    let quit: () -> Void

    var body: some View {
        Toggle("开机自启动", isOn: Binding(get: { lifecycle.loginStatus == "enabled" || lifecycle.loginStatus == "requires_approval" }, set: { enabled in
            do { try lifecycle.setStartAtLogin(enabled) } catch { lifecycle.showError(error) }
        }))
        if lifecycle.loginStatus == "requires_approval" {
            Button("在系统设置中允许自启动") { SMAppService.openSystemSettingsLoginItems() }
        }
        Button("检查更新") {
            do { try lifecycle.checkForUpdates() } catch { lifecycle.showError(error) }
        }.disabled(lifecycle.busy)
        Button("通过 Homebrew 更新并重启") {
            do { try lifecycle.updateAndRestart() } catch { lifecycle.showError(error) }
        }.disabled(lifecycle.busy)
        Button("重启星盘") {
            do { try lifecycle.restart() } catch { lifecycle.showError(error) }
        }.disabled(lifecycle.busy)
        Divider()
        Button("退出星盘", action: quit).disabled(lifecycle.busy)
    }
}

private struct LifecycleMessage: View {
    @ObservedObject var lifecycle: AppLifecycle

    var body: some View {
        if let message = lifecycle.message {
            Text(message).font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct AwakeSummary: View {
    @ObservedObject var awake: KeepAwake

    var body: some View {
        if awake.isActive {
            HStack {
                Label("防休眠", systemImage: "cup.and.saucer.fill")
                Text(MetricText.countdown(awake.remaining)).monospacedDigit()
                Spacer()
                Button("结束") { awake.stop() }.accessibilityLabel("结束防休眠")
            }
            .font(.caption).foregroundStyle(.indigo)
            .padding(10)
            .background(Color.indigo.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
        }
    }
}

private struct MetricCard: View {
    let title: String
    let icon: String
    let color: Color
    let value: String
    let detail: String
    let fraction: Double?
    let compact: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 5 : 8) {
            Label(title, systemImage: icon).font(.caption).foregroundStyle(color)
            Text(value).font(.system(size: compact ? 17 : 21, weight: .semibold, design: .rounded))
                .monospacedDigit().lineLimit(1).minimumScaleFactor(0.65)
            Text(detail).font(.caption).foregroundStyle(.secondary).lineLimit(1).minimumScaleFactor(0.75)
            if !compact, let fraction {
                ProgressView(value: min(1, max(0, fraction))).tint(color).accessibilityHidden(true)
            }
        }
        .frame(maxWidth: .infinity, minHeight: compact ? 64 : 94, alignment: .leading)
        .padding(12)
        .background(color.opacity(0.065), in: RoundedRectangle(cornerRadius: 13))
        .overlay(RoundedRectangle(cornerRadius: 13).strokeBorder(color.opacity(0.12), lineWidth: 1))
        .accessibilityElement(children: .combine)
    }
}

private struct AwakeView: View {
    @ObservedObject var awake: KeepAwake
    @Binding var minutes: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                Label("定时防休眠", systemImage: awake.isActive ? "cup.and.saucer.fill" : "cup.and.saucer")
                    .font(.subheadline.weight(.medium))
                Spacer()
                if awake.isActive {
                    Text(MetricText.countdown(awake.remaining)).monospacedDigit().font(.subheadline)
                        .foregroundStyle(.indigo).accessibilityLabel("剩余 \(MetricText.countdown(awake.remaining))")
                }
            }
            HStack {
                Picker("持续时间", selection: $minutes) {
                    Text("15 分钟").tag(15)
                    Text("30 分钟").tag(30)
                    Text("1 小时").tag(60)
                    Text("2 小时").tag(120)
                }
                .labelsHidden().disabled(awake.isActive)
                .accessibilityLabel("防休眠持续时间")
                Spacer()
                Button(awake.isActive ? "结束" : "开始") {
                    if awake.isActive { awake.stop() } else { awake.start(seconds: TimeInterval(minutes * 60)) }
                }
                .buttonStyle(.borderedProminent).tint(.indigo)
                .accessibilityLabel(awake.isActive ? "结束防休眠" : "开始防休眠")
            }
            Text("允许屏幕熄灭，不改变合盖或手动睡眠。")
                .font(.caption2).foregroundStyle(.secondary)
            if let message = awake.message {
                Text(message).font(.caption).foregroundStyle(.red).fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(12)
        .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 13))
    }
}
