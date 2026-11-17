# StarDash

星盘：Mac 菜单栏状态面板与小悬浮窗口。当前为 0.1.0 本地体验版，使用 Swift、SwiftUI 和 AppKit，无第三方依赖。

## 已实现

- CPU 总使用率、已用／总内存、实时上传与下载、电池电量及供电状态。
- 菜单栏展开面板与可拖动悬浮窗口，共享数据和设置。
- 精简／展开、窗口置顶、显示项目选择；保存窗口位置、显示方式及防休眠时长。
- 15 分钟、30 分钟、1 小时、2 小时定时防休眠；显示倒计时，可随时结束，精简状态下也能结束。
- 展示时每 2 秒采样，隐藏时每 10 秒采样；首次 CPU／网速采样等待增量。

无内置电池时隐藏电池卡；采集失败时显示不可用。音量、音频设备切换和锁屏按需求不提供。

## 构建与运行

需要 macOS 和 Swift 工具链（Xcode 或 Command Line Tools）。

```sh
./scripts/build.sh
open build/StarDash.app
```

脚本构建 release、组装应用、进行本地临时签名并运行自检。首次运行从菜单栏的闪光图标打开面板；右上角可切换为悬浮窗口，底部“更多”可退出。也可在未运行时直接打开悬浮窗口：

```sh
open build/StarDash.app --args --show-window
```

设置保存在本机 UserDefaults；重启恢复显示设置和窗口位置，防休眠任务不会在重启后自动恢复。

## 验证

```sh
build/StarDash.app/Contents/MacOS/StarDash --self-test
build/StarDash.app/Contents/MacOS/StarDash --power-test
build/StarDash.app/Contents/MacOS/StarDash --diagnostics
```

- `--self-test`：16 项计算、计数溢出、接口重置、格式及本机采集检查。
- `--power-test`：短时创建实际防休眠任务，检查系统超时、到期和手动清理；结束后释放。
- `--diagnostics`：输出一次真实采集的 JSON，不打开界面。

本机验证记录见 [验证记录](docs/verification.md)，产品范围和历史依据见 [需求文档](docs/product-requirements.md)。

## 当前限制

- 仅在 Apple Silicon、macOS 27.2.1 上构建和实测；最低 macOS 13 是项目声明，其他系统版本与 Intel 尚未验证。本次 ZIP 仅含 arm64 应用。
- 本地临时签名（ad-hoc），尚未进行 Apple 开发者签名或公证，下载后可能被系统拦截；正式分发前仍需完成签名与公证。
- 内存为扣除可回收缓存后的估算，可能与活动监视器不同；网速合计活动的 `en` 以太网／Wi-Fi 接口，不重复累计 VPN 虚拟接口。
- 防休眠仅阻止空闲导致的系统睡眠，允许屏幕熄灭；不改变合盖、手动睡眠或系统电量保护行为。
- 图标收纳、自动更新、全局快捷键、多主题、趋势图和其他系统控制尚未实现。未运行或接入旧收纳原型。
- 多屏、全屏应用及长时间资源占用尚未专项验证。

## 许可证 / License

本项目采用 [MIT](LICENSE) 许可证。

This project is licensed under the [MIT License](LICENSE).
