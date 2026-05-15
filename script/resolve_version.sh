#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  script/resolve_version.sh [--next] [--offset N]

Computes the app version from Git history.
--next      Include the commit that is about to be created by pre-commit.
--offset N  Test helper: compute BASE_VERSION + N patch-style increments.
EOF
}

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "$script_dir/version.env"

next=false
offset_override=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --next)
      next=true
      shift
      ;;
    --offset)
      [[ $# -ge 2 ]] || { usage >&2; exit 2; }
      offset_override="$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      usage >&2
      exit 2
      ;;
  esac
done

IFS='.' read -r base_major base_minor base_patch <<< "$BASE_VERSION"

if [[ -n "$offset_override" ]]; then
  offset="$offset_override"
else
  if ! git cat-file -e "$BASE_COMMIT^{commit}" 2>/dev/null; then
    echo "Base commit not found: $BASE_COMMIT" >&2
    exit 1
  fi
  offset="$(git rev-list --count "${BASE_COMMIT}..HEAD")"
  if [[ "$next" == true ]]; then
    offset=$((offset + 1))
  fi
fi

if ! [[ "$offset" =~ ^[0-9]+$ ]]; then
  echo "Offset must be a non-negative integer: $offset" >&2
  exit 2
fi

total_patch=$((base_patch + offset))
major=$base_major
minor=$base_minor
patch=$total_patch

minor=$((minor + patch / 10))
patch=$((patch % 10))
major=$((major + minor / 10))
minor=$((minor % 10))

printf '%d.%d.%d\n' "$major" "$minor" "$patch"
