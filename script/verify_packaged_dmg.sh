#!/usr/bin/env bash
set -euo pipefail

if [[ $# -lt 2 || $# -gt 4 ]]; then
  echo "Usage: $0 /path/to/package.dmg AppName [expected-marketing-version] [expected-build-version]" >&2
  exit 2
fi

dmg_path="$1"
app_name="$2"
expected_marketing_version="${3:-}"
expected_build_version="${4:-}"
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
expect_signed_release="${EXPECT_SIGNED_RELEASE:-0}"
expect_notarized_dmg="${EXPECT_NOTARIZED_DMG:-0}"

if [[ ! -f "$dmg_path" ]]; then
  echo "DMG not found: $dmg_path" >&2
  exit 1
fi

if [[ "$expect_signed_release" == "1" ]]; then
  codesign --verify --verbose=4 "$dmg_path"
fi

if [[ "$expect_notarized_dmg" == "1" ]]; then
  xcrun stapler validate "$dmg_path"
  spctl -a -vvv --type open --context context:primary-signature "$dmg_path"
fi

mountpoint="$(mktemp -d)"
attached_device=""
copied_root=""

cleanup() {
  if [[ -n "$attached_device" ]]; then
    hdiutil detach "$attached_device" >/dev/null 2>&1 || true
  fi
  rm -rf "$mountpoint" "$copied_root"
}
trap cleanup EXIT

attach_plist="$(mktemp)"
hdiutil attach -mountpoint "$mountpoint" -nobrowse -readonly -plist "$dmg_path" > "$attach_plist"

attached_device="$(/usr/bin/python3 - "$attach_plist" <<'PY'
import plistlib
import sys
from pathlib import Path

data = plistlib.loads(Path(sys.argv[1]).read_bytes())
for entity in data.get("system-entities", []):
    dev = entity.get("dev-entry")
    if dev:
        print(dev)
        break
PY
)"
rm -f "$attach_plist"

app_bundle="$mountpoint/$app_name.app"
applications_link="$mountpoint/Applications"

if [[ ! -d "$app_bundle" ]]; then
  echo "Packaged app missing from DMG: $app_bundle" >&2
  exit 1
fi

if [[ ! -L "$applications_link" ]]; then
  echo "Applications symlink missing from DMG: $applications_link" >&2
  exit 1
fi

copied_root="$(mktemp -d)"
copied_app="$copied_root/$app_name.app"
ditto "$app_bundle" "$copied_app"

"$script_dir/verify_release_app.sh" "$copied_app" "$expected_marketing_version" "$expected_build_version"

if [[ "$expect_notarized_dmg" == "1" ]]; then
  xcrun stapler validate "$copied_app"
  spctl -a -vvv --type execute "$copied_app"
fi
