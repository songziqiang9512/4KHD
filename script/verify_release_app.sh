#!/usr/bin/env bash
set -euo pipefail

if [[ $# -lt 1 || $# -gt 3 ]]; then
  echo "Usage: $0 /path/to/App.app [expected-marketing-version] [expected-build-version]" >&2
  exit 2
fi

app_path="$1"
expected_marketing_version="${2:-}"
expected_build_version="${3:-}"

if [[ ! -d "$app_path" ]]; then
  echo "App bundle not found: $app_path" >&2
  exit 1
fi

info_plist="$app_path/Contents/Info.plist"
executable_name="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$info_plist")"
executable_path="$app_path/Contents/MacOS/$executable_name"
entitlements_path="$(mktemp)"
trap '/bin/rm -f "$entitlements_path"' EXIT

codesign --verify --strict --deep --verbose=4 "$app_path"
# `codesign -d --entitlements <path>` emits a diagnostic tree rather than a
# plist on current macOS. The `:-` display target still emits parseable XML to
# stdout, which lets this gate assert the final sealed entitlements.
codesign -d --entitlements :- "$app_path" > "$entitlements_path"

assert_plist_value() {
  local plist_path="$1"
  local key="$2"
  local expected="$3"
  local actual
  actual="$(/usr/libexec/PlistBuddy -c "Print :$key" "$plist_path" 2>/dev/null || true)"
  if [[ "$actual" != "$expected" ]]; then
    echo "Unexpected $key in $plist_path: expected '$expected', got '${actual:-<missing>}'" >&2
    exit 1
  fi
}

for entitlement_key in \
  com.apple.security.app-sandbox \
  com.apple.security.assets.pictures.read-write \
  com.apple.security.files.downloads.read-write \
  com.apple.security.files.user-selected.read-write \
  com.apple.security.files.bookmarks.app-scope \
  com.apple.security.network.client
do
  assert_plist_value "$entitlements_path" "$entitlement_key" true
done

bundle_identifier="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$info_plist")"
mach_lookup_values="$(/usr/libexec/PlistBuddy -c 'Print :com.apple.security.temporary-exception.mach-lookup.global-name' "$entitlements_path" 2>/dev/null || true)"
for service_suffix in spks spki; do
  expected_service="$bundle_identifier-$service_suffix"
  if ! grep -Fq "$expected_service" <<< "$mach_lookup_values"; then
    echo "Missing Sparkle mach-lookup entitlement: $expected_service" >&2
    exit 1
  fi
done

assert_plist_value "$info_plist" SUEnableInstallerLauncherService true
assert_plist_value "$info_plist" SUVerifyUpdateBeforeExtraction true

sparkle_public_key="$(/usr/libexec/PlistBuddy -c 'Print :SUPublicEDKey' "$info_plist" 2>/dev/null || true)"
if [[ -z "$sparkle_public_key" || "$sparkle_public_key" == *'$('* ]]; then
  echo "SUPublicEDKey is missing or unresolved" >&2
  exit 1
fi

if [[ -n "$expected_marketing_version" ]]; then
  assert_plist_value "$info_plist" CFBundleShortVersionString "$expected_marketing_version"
fi
if [[ -n "$expected_build_version" ]]; then
  assert_plist_value "$info_plist" CFBundleVersion "$expected_build_version"
fi

if [[ ! -d "$app_path/Contents/Frameworks/Sparkle.framework" ]]; then
  echo "Embedded Sparkle.framework is missing" >&2
  exit 1
fi

assert_developer_id_timestamp() {
  local signed_path="$1"
  local signing_info
  signing_info="$(codesign -d --verbose=4 "$signed_path" 2>&1)"
  if ! grep -Fq 'Authority=Developer ID Application:' <<< "$signing_info"; then
    echo "Developer ID Application signature missing: $signed_path" >&2
    exit 1
  fi
  if ! grep -Eq '^Timestamp=.+$' <<< "$signing_info"; then
    echo "Secure timestamp missing: $signed_path" >&2
    exit 1
  fi
}

sparkle_version="$app_path/Contents/Frameworks/Sparkle.framework/Versions/B"
for signed_path in \
  "$sparkle_version/XPCServices/Installer.xpc" \
  "$sparkle_version/XPCServices/Downloader.xpc" \
  "$sparkle_version/Autoupdate" \
  "$sparkle_version/Updater.app" \
  "$app_path/Contents/Frameworks/Sparkle.framework" \
  "$app_path"
do
  assert_developer_id_timestamp "$signed_path"
done

architectures="$(lipo -archs "$executable_path")"
if ! grep -qw arm64 <<< "$architectures"; then
  echo "Expected arm64 release executable, got: $architectures" >&2
  exit 1
fi

echo "Verified release app: $app_path"
