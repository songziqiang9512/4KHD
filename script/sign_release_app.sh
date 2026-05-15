#!/usr/bin/env bash
set -euo pipefail

if [[ $# -lt 2 || $# -gt 3 ]]; then
  echo "Usage: $0 /path/to/App.app 'Developer ID Application: ...' [/path/to/keychain]" >&2
  exit 2
fi

app_path="$1"
identity="$2"
keychain_path="${3:-}"

if [[ ! -d "$app_path" ]]; then
  echo "App bundle not found: $app_path" >&2
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
  codesign "${codesign_args[@]}" "$path"
}

while IFS= read -r binary_path; do
  [[ -n "$binary_path" ]] || continue
  sign_path "$binary_path"
done < <(
  find "$app_path/Contents" -type f ! -path '*/_CodeSignature/*' -print \
    | while IFS= read -r candidate; do
        if file -b "$candidate" | grep -q 'Mach-O'; then
          printf '%s\t%s\n' "$(awk -F/ '{print NF}' <<<"$candidate")" "$candidate"
        fi
      done \
    | sort -rn \
    | cut -f2-
)

while IFS= read -r nested_bundle; do
  [[ -n "$nested_bundle" ]] || continue
  [[ "$nested_bundle" == "$app_path" ]] && continue
  sign_path "$nested_bundle"
done < <(
  find "$app_path/Contents" \
    \( -name '*.app' -o -name '*.appex' -o -name '*.framework' -o -name '*.xpc' \) \
    -print \
    | awk '{ print gsub(/\//, "&") "\t" $0 }' \
    | sort -rn \
    | cut -f2-
)

sign_path "$app_path"
codesign --verify --strict --deep --verbose=4 "$app_path"
