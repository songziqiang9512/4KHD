#!/usr/bin/env bash
set -euo pipefail

if [[ $# -lt 2 || $# -gt 3 ]]; then
  echo "Usage: $0 /path/to/App.app 'Developer ID Application: ...' [/path/to/keychain]" >&2
  exit 2
fi

app_path="$1"
identity="$2"
keychain_path="${3:-}"
sparkle_framework="$app_path/Contents/Frameworks/Sparkle.framework"
sparkle_version="$sparkle_framework/Versions/B"

if [[ ! -d "$app_path" ]]; then
  echo "App bundle not found: $app_path" >&2
  exit 1
fi
if [[ ! -d "$sparkle_version" ]]; then
  echo "Sparkle framework version B not found: $sparkle_version" >&2
  exit 1
fi

codesign_args=(
  --force
  --timestamp
  --options runtime
  --sign "$identity"
)
if [[ -n "$keychain_path" ]]; then
  codesign_args+=(--keychain "$keychain_path")
fi

sign_path() {
  local path="$1"
  [[ -e "$path" ]] || { echo "Sparkle signing target missing: $path" >&2; exit 1; }
  codesign "${codesign_args[@]}" "$path"
}

# Sparkle's distribution guide requires this inner-to-outer order. Downloader
# carries a sandbox entitlement in current Sparkle releases, so preserve it.
sign_path "$sparkle_version/XPCServices/Installer.xpc"
codesign "${codesign_args[@]}" --preserve-metadata=entitlements \
  "$sparkle_version/XPCServices/Downloader.xpc"
sign_path "$sparkle_version/Autoupdate"
sign_path "$sparkle_version/Updater.app"
sign_path "$sparkle_framework"

# Re-seal the host after changing its nested framework without losing the
# entitlements produced by Xcode from the target's build settings.
codesign "${codesign_args[@]}" --preserve-metadata=entitlements,requirements \
  "$app_path"

codesign --verify --strict --deep --verbose=4 "$app_path"
