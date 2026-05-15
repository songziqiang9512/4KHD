#!/usr/bin/env bash
set -euo pipefail

if [[ $# -lt 2 || $# -gt 3 ]]; then
  echo "Usage: $0 /path/to/App.app /path/to/output.dmg [display-name]" >&2
  exit 2
fi

app_path="$1"
output_dmg="$2"
display_name="${3:-$(basename "$app_path" .app)}"

if [[ ! -d "$app_path" ]]; then
  echo "App bundle not found: $app_path" >&2
  exit 1
fi

mkdir -p "$(dirname "$output_dmg")"
rm -f "$output_dmg"

staging_dir="$(mktemp -d)"
cleanup() {
  rm -rf "$staging_dir"
}
trap cleanup EXIT

cp -R "$app_path" "$staging_dir/"
ln -s /Applications "$staging_dir/Applications"

hdiutil create \
  -volname "$display_name" \
  -srcfolder "$staging_dir" \
  -ov \
  -format UDZO \
  "$output_dmg"
