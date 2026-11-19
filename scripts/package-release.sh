#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
[[ "$(uname -m)" == arm64 ]] || { print -u2 '此打包脚本仅支持 Apple Silicon。'; exit 1; }
./scripts/build.sh
release_version=$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' Resources/Info.plist)
[[ "$release_version" =~ '^[0-9]+\.[0-9]+\.[0-9]+$' ]] || { print -u2 '版本号无效'; exit 1; }
release_dir="$PWD/build/release"
mkdir -p "$release_dir"
archive_name="StarDash-${release_version}-macos-arm64.zip"
/usr/bin/ditto -c -k --sequesterRsrc --keepParent build/StarDash.app "$release_dir/$archive_name"
archive_sha=$(/usr/bin/shasum -a 256 "$release_dir/$archive_name" | /usr/bin/cut -d ' ' -f 1)
printf '%s  %s\n' "$archive_sha" "$archive_name" > "$release_dir/SHA256SUMS"
cat > "$release_dir/stardash.rb" <<EOF
cask "stardash" do
  version "$release_version"
  sha256 "$archive_sha"

  url "https://github.com/StarDreamTech/StarDash/releases/download/v#{version}/StarDash-#{version}-macos-arm64.zip"
  name "StarDash"
  desc "Mac status panel, timed keep-awake and terminal command shortcuts"
  homepage "https://github.com/StarDreamTech/StarDash"

  depends_on arch: :arm64
  depends_on macos: ">= :ventura"

  app "StarDash.app"
  binary "#{appdir}/StarDash.app/Contents/Resources/stardash-cli", target: "stardash"
end
EOF
printf '已准备 ZIP、SHA256SUMS、stardash.rb：%s\n未创建 Release，也未发布 Homebrew。\n' "$release_dir"
