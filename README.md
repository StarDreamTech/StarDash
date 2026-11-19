# StarDash

星盘：Mac 菜单栏状态面板与小悬浮窗口。当前为 0.3.0 本地体验版，使用 Swift、SwiftUI 和 AppKit，无第三方依赖。

## 已实现

- CPU 总使用率、已用／总内存、实时上传与下载、电池电量及供电状态。
- 菜单栏展开面板与可拖动悬浮窗口，共享数据和设置。
- 精简／展开、窗口置顶、显示项目选择；保存窗口位置、显示方式及防休眠时长。
- 15 分钟、30 分钟、1 小时、2 小时定时防休眠；显示倒计时，可随时结束，精简状态下也能结束。
- 展示时每 2 秒采样，隐藏时每 10 秒采样；首次 CPU／网速采样等待增量。
- 自定义命令快捷图标：设置名称、图标和命令，点击后打开系统终端执行；右键编辑或删除，重启保留。
- macOS 登录自启动开关、手动检查更新、通过 Homebrew 更新并重启、单独重启。
- `stardash` CLI：读取状态和指标、切换面板、控制设置与防休眠、管理和运行命令、自启与更新；提供 JSON 输出。
- 随应用打包的 AI Skill，可安装到 Codex 或 Claude 的技能目录。

无内置电池时隐藏电池卡；采集失败时显示不可用。音量、音频设备切换和锁屏按需求不提供。

## 构建与运行

需要 macOS 和 Swift 工具链（Xcode 或 Command Line Tools）。

```sh
./scripts/build.sh
open build/StarDash.app
```

脚本构建 release、组装应用、进行本地临时签名并运行自检。首次运行从菜单栏的闪光图标打开面板；右上角可切换为悬浮窗口，底部“更多”提供自启、更新、重启和退出。也可在未运行时直接打开悬浮窗口：

```sh
open build/StarDash.app --args --show-window
```

设置保存在本机 UserDefaults；重启恢复显示设置和窗口位置，防休眠任务不会在重启后自动恢复。

## 自启动、更新与 Homebrew 状态

“更多 → 开机自启动”使用 macOS 登录项服务，默认关闭。系统要求审批时，在“系统设置 → 通用 → 登录项”中允许星盘；只有服务状态为 `enabled` 才算开启。此处“开机”指用户登录后启动，不是在登录前运行。

“检查更新”查询官方 GitHub Release。“通过 Homebrew 更新并重启”只适用于官方 Cask 安装到 `/Applications/StarDash.app` 或 `~/Applications/StarDash.app` 的应用：检查安装来源、执行 Homebrew 更新与升级、检查新版本，然后重启。升级失败时保留当前进程并显示原因；日志保存在 `~/Library/Logs/StarDash/update.log`。重启会结束当前防休眠任务。

**截至 2026-11-19，StarDash 尚无 GitHub Release，官方 Homebrew 源也没有 `stardash`。当前检查更新会如实显示未发布，不能宣称已能在线升级。** 打包脚本可以生成 ZIP、SHA256 和真实 Cask 文件，但不会自行发布。发布步骤见 [发布说明](docs/releasing.md)。

## CLI 与 AI Skill

源码构建后，可以直接调用包内入口，或将它链接为 `stardash`：

```sh
build/StarDash.app/Contents/Resources/stardash-cli help
./scripts/install-cli.sh
stardash status
stardash metrics
stardash show floating
stardash awake start --minutes 30
stardash awake stop
```

安装脚本只链接到 `~/.local/bin/stardash`，不会覆盖已有的其他文件；该目录需要在 PATH 中。包内入口放在 Resources，避免 macOS 不区分大小写导致 `stardash` 覆盖 `StarDash` 主程序。Homebrew 正式发布后，Cask 将自动提供同名命令。

AI 调用说明随软件放在 `Contents/Resources/skills/stardash/SKILL.md`，仓库源文件见 [StarDash Skill](skills/stardash/SKILL.md)。安装到当前用户的 AI 工具：

```sh
stardash skill install codex
stardash skill install claude
```

Codex 使用 `$CODEX_HOME/skills/stardash`，未设置时使用 `~/.codex/skills/stardash`；Claude 使用 `~/.claude/skills/stardash`。已有不同内容不会被覆盖。AI 重新加载技能后，可按自然语言需求调用 CLI。完整命令、JSON 结果和异步任务规则见 [CLI 说明](docs/cli.md)。

## 命令快捷图标

在面板“命令快捷方式”右侧点击加号，输入名称、选择图标、填写命令后保存。保存只创建图标；点击图标时才打开系统终端执行，输出与交互都留在终端。右键图标可编辑或删除，删除前会确认。精简模式也保留命令图标。

命令使用登录、交互式 zsh，读取用户的 zsh 环境，默认从个人主目录执行。需要指定项目目录时，把 `cd` 写在命令中，例如：

```sh
cd ~/git_pro/StarDash && swift build
```

支持管道、引号、中文和多行输入。每次点击都是一次独立执行；命令是否成功以终端输出为准。命令原文保存在本机 UserDefaults，执行时生成仅本人可读写执行的临时脚本，脚本开始运行后自行删除；终端启动失败时也会清理并在面板显示错误。保存、恢复配置和启动星盘不会执行命令。

## 验证

```sh
build/StarDash.app/Contents/MacOS/StarDash --self-test
build/StarDash.app/Contents/MacOS/StarDash --power-test
build/StarDash.app/Contents/MacOS/StarDash --diagnostics
python3 scripts/test-cli.py
```

- `--self-test`：原有 16 项指标检查，加上命令校验、保存／编辑／删除／恢复、损坏数据保护、脚本权限、真实 zsh 转义执行、退出码及临时清理检查。
- `--power-test`：短时创建实际防休眠任务，检查系统超时、到期和手动清理；结束后释放。
- `--diagnostics`：输出一次真实采集的 JSON，不打开界面。
- `scripts/test-cli.py`：验证包内／符号链接入口、JSON 与错误、真实应用通信、设置、命令增改删、防休眠、更新查询、Skill 安装保护和重启退出；恢复测试设置并删除测试条目。

本机验证记录见 [验证记录](docs/verification.md)，产品范围和历史依据见 [需求文档](docs/product-requirements.md)。

## 当前限制

- 仅在 Apple Silicon、macOS 27.2.1 上构建和实测；最低 macOS 13 是项目声明，其他系统版本与 Intel 尚未验证。本次 ZIP 仅含 arm64 应用。
- 本地临时签名（ad-hoc），尚未进行 Apple 开发者签名或公证，下载后可能被系统拦截；正式分发前仍需完成签名与公证。
- 内存为扣除可回收缓存后的估算，可能与活动监视器不同；网速合计活动的 `en` 以太网／Wi-Fi 接口，不重复累计 VPN 虚拟接口。
- 防休眠仅阻止空闲导致的系统睡眠，允许屏幕熄灭；不改变合盖、手动睡眠或系统电量保护行为。
- 在线升级依赖尚待发布的 Release 和 Homebrew Cask；当前仅完成升级路径及检查／错误处理，未做真实版本间升级。后台自动下载更新尚未实现。
- 图标收纳、全局快捷键、多主题、趋势图和其他系统控制尚未实现。未运行或接入旧收纳原型。
- 多屏、全屏应用及长时间资源占用尚未专项验证。

## 许可证 / License

本项目采用 [MIT](LICENSE) 许可证。

This project is licensed under the [MIT License](LICENSE).
