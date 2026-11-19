# StarDash 发布准备

截至 2026-11-19，只交付本地体验包，尚无 GitHub Release，也未把 StarDash 加入 `StarDreamTech/homebrew-tap`。下文是待执行的发布流程，不代表已经发布。

## 生成材料

在 Apple Silicon Mac 上执行：

```sh
./scripts/package-release.sh
```

脚本读取 `Resources/Info.plist` 的版本，构建并验证应用，生成：

- `build/release/StarDash-VERSION-macos-arm64.zip`
- `build/release/SHA256SUMS`
- `build/release/stardash.rb`

文件名中的 VERSION 是实际版本号；生成的 Cask 包含该 ZIP 的真实 SHA256、正式下载 URL、最低 macOS 13 声明、arm64 限制、应用与 `stardash` CLI 入口。脚本不会创建标签、上传文件或修改 Homebrew 源。

当前构建使用本地临时签名，没有 Apple 开发者签名或公证。公开分发前需完成正式签名／公证及相应安装验证；若重签或重新归档导致 ZIP 变化，必须重新生成校验和并更新 Cask，不得沿用旧 SHA256。

## 正式发布顺序

1. 确认版本、提交、签名、公证和安装验证，再为对应提交创建 `vVERSION` Release，上传同名 ZIP 与校验和。
2. 验证公开下载的 ZIP 与 SHA256，再把生成的 `stardash.rb` 加入官方 Homebrew 仓库的 `Casks/`；按该仓库流程审查并发布。
3. 从干净安装测试以下命令。**目前没有公开 Cask，尚不能使用这一安装命令。**

```sh
brew install --cask stardreamtech/tap/stardash
stardash version
stardash status
stardash skill install codex
```

4. 后续发布较新版本时，在旧版本的 Homebrew 安装上验证“更新并重启”：新 PID、新版本，原设置和快捷命令保留，防休眠结束；同时验证升级失败时当前进程继续运行。

应用内更新使用 Homebrew 的校验、安装和失败处理，不自行下载覆盖应用。不支持后台自动检查／下载，也不处理任意自定义 `appdir`。Cask 不含卸载前强制退出步骤，避免 Homebrew 自更新中途终止正在执行升级的进程；卸载应用时应先通过星盘或 `stardash quit` 退出。
