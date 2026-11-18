[简体中文](README.md) | **English**

<img src="assets/stardash.svg" width="96" height="96" alt="StarDash logo" />

# StarDash

StarDash (星盘) is a Mac menu bar status panel and a small floating window. The current version is 0.2.0, a local preview built with Swift, SwiftUI, and AppKit, with no third-party dependencies.

## Implemented features

- Overall CPU usage, used and total memory, live upload and download speeds, battery level, and power source status.
- A menu bar panel and a draggable floating window that share data and settings.
- Compact and expanded views, an always-on-top option, and a choice of visible metrics; window position, display mode, and keep-awake duration are saved.
- Timed keep-awake sessions of 15 minutes, 30 minutes, 1 hour, or 2 hours, with a countdown and the option to stop at any time, including in compact view.
- Sampling every 2 seconds while visible and every 10 seconds while hidden; the first CPU and network readings wait for a second sample to calculate the change.
- Custom command shortcut icons: set a name, icon, and command, then click to run it in the system Terminal app; right-click to edit or delete. Shortcuts persist across restarts.

The battery card is hidden on Macs without a built-in battery. Failed readings are shown as unavailable. Volume controls, audio output switching, and screen locking are intentionally excluded from the product scope.

## Build and run

Requires macOS and a Swift toolchain, provided by Xcode or Command Line Tools.

```sh
./scripts/build.sh
open build/StarDash.app
```

The script builds a release executable, assembles the app bundle, applies a local ad-hoc signature, and runs the self-tests. On first launch, click the sparkles icon in the menu bar to open the panel. Use the button at the top right to switch to a floating window, or the More menu (更多) at the bottom to quit. When the app is not already running, you can also launch directly into the floating window:

```sh
open build/StarDash.app --args --show-window
```

Settings are stored locally in UserDefaults. Display settings and window position are restored after restarting the app; keep-awake sessions are not resumed automatically.

## Command shortcut icons

Click the plus button beside Command Shortcuts (命令快捷方式), enter a name, choose an icon, enter a command, and save. Saving only creates the icon. Clicking that icon opens the system Terminal app and runs the command, with output and interaction kept in Terminal. Right-click an icon to edit or delete it; deletion requires confirmation. Command icons remain available in compact view.

Commands run in a login, interactive zsh that loads your zsh environment. The initial working directory is your home directory. Include `cd` in the command to use a specific project directory, for example:

```sh
cd ~/git_pro/StarDash && swift build
```

Pipes, quotes, Chinese text, and multiple lines are supported. Each click starts a separate execution; use the Terminal output to determine whether the command succeeded. Command text is stored locally in UserDefaults. Each execution creates a temporary script that only its owner can read, write, or execute. The script deletes itself when execution begins. If Terminal cannot be opened, the temporary script is also cleaned up and an error is shown in the panel. Saving shortcuts, restoring settings, and launching StarDash do not execute commands.

## Verification

```sh
build/StarDash.app/Contents/MacOS/StarDash --self-test
build/StarDash.app/Contents/MacOS/StarDash --power-test
build/StarDash.app/Contents/MacOS/StarDash --diagnostics
```

- `--self-test`: the original 16 metric checks, plus command validation, save/edit/delete/restore behavior, corrupt-data protection, script permissions, actual zsh execution with quoting, exit codes, and temporary-file cleanup.
- `--power-test`: briefly creates a real keep-awake session and checks the system timeout, expiration, and manual cleanup; the assertion is released afterward.
- `--diagnostics`: prints one sample of real metrics as JSON without opening the interface.

See the [local verification record](docs/verification.md) and [product requirements](docs/product-requirements.md) for the tested behavior, product scope, and historical context. Both linked documents are currently in Chinese.

## Current limitations

- Built and tested only on Apple Silicon with macOS 27.2.1. macOS 13 is the declared minimum; other macOS versions and Intel Macs have not been verified. The current ZIP contains only an arm64 app.
- The app uses a local ad-hoc signature and has not received an Apple Developer signature or notarization. macOS may block the downloaded app; proper signing and notarization are still required before general distribution.
- Memory usage is an estimate that excludes reclaimable cache and may differ from Activity Monitor. Network speeds combine active `en` Ethernet/Wi-Fi interfaces without double-counting virtual VPN interfaces.
- Keep-awake only prevents idle system sleep while allowing the display to turn off. It does not change lid-close behavior, manual sleep, or the system's battery protection behavior.
- Menu bar icon organization, automatic updates, global keyboard shortcuts, multiple themes, trend charts, and other system controls are not implemented. The old icon-organization prototype has not been run or integrated.
- Multiple displays, full-screen apps, and long-term resource usage have not received dedicated testing.

## License

This project is licensed under the [MIT](LICENSE) license.
