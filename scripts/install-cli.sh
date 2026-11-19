#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
cli_source="$PWD/build/StarDash.app/Contents/Resources/stardash-cli"
cli_dir="$HOME/.local/bin"
cli_target="$cli_dir/stardash"
[[ -x "$cli_source" ]] || { print -u2 '请先运行 ./scripts/build.sh'; exit 1; }
mkdir -p "$cli_dir"
if [[ -e "$cli_target" || -L "$cli_target" ]]; then
  [[ -L "$cli_target" && "${cli_target:A}" == "$cli_source" ]] || { print -u2 "目标已存在，未覆盖：$cli_target"; exit 1; }
else
  ln -s "$cli_source" "$cli_target"
fi
"$cli_target" version
printf 'CLI 已链接到 %s；若不在 PATH，请将 ~/.local/bin 加入 PATH。\n' "$cli_target"
