#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
swift build -c release
artifact_dir="$(swift build -c release --show-bin-path)"
app_dir="$PWD/build/StarDash.app"
mkdir -p "$app_dir/Contents/MacOS" "$app_dir/Contents/Resources"
cp "$artifact_dir/StarDash" "$app_dir/Contents/MacOS/StarDash"
cp Resources/Info.plist "$app_dir/Contents/Info.plist"
cp scripts/stardash "$app_dir/Contents/Resources/stardash-cli"
chmod 755 "$app_dir/Contents/Resources/stardash-cli"
mkdir -p "$app_dir/Contents/Resources/skills"
ditto skills/stardash "$app_dir/Contents/Resources/skills/stardash"
codesign --force --sign - --identifier tech.stardream.StarDash "$app_dir"
codesign --verify --strict "$app_dir"
"$app_dir/Contents/MacOS/StarDash" --self-test
"$app_dir/Contents/Resources/stardash-cli" version
printf '已构建：%s\n' "$app_dir"
