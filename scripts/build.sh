#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
swift build -c release
artifact_dir="$(swift build -c release --show-bin-path)"
app_dir="$PWD/build/StarDash.app"
mkdir -p "$app_dir/Contents/MacOS" "$app_dir/Contents/Resources"
cp "$artifact_dir/StarDash" "$app_dir/Contents/MacOS/StarDash"
cp Resources/Info.plist "$app_dir/Contents/Info.plist"
codesign --force --sign - --identifier tech.stardream.StarDash "$app_dir"
codesign --verify --strict "$app_dir"
"$artifact_dir/StarDash" --self-test
printf '已构建：%s\n' "$app_dir"
