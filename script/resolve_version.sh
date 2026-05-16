#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  script/resolve_version.sh [--next] [--offset N]

Computes the app version from the latest build-* release tag.
--next      Advance one release beyond the latest released version.
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

increment_version() {
  local version="$1"
  local major minor patch
  IFS='.' read -r major minor patch <<< "$version"
  patch=$((patch + 1))
  if (( patch >= 10 )); then
    patch=0
    minor=$((minor + 1))
  fi
  if (( minor >= 10 )); then
    minor=0
    major=$((major + 1))
  fi
  printf '%d.%d.%d\n' "$major" "$minor" "$patch"
}

if [[ -n "$offset_override" ]]; then
  version="$BASE_VERSION"
  offset="$offset_override"
  if ! [[ "$offset" =~ ^[0-9]+$ ]]; then
    echo "Offset must be a non-negative integer: $offset" >&2
    exit 2
  fi
  while (( offset > 0 )); do
    version="$(increment_version "$version")"
    offset=$((offset - 1))
  done
  printf '%s\n' "$version"
  exit 0
fi

latest_tag="$(git tag --list 'build-*' --sort=-version:refname | head -n 1 || true)"
if [[ -z "$latest_tag" ]]; then
  latest_tag="$(
    git ls-remote --tags origin 'build-*' 2>/dev/null \
      | awk -F'/' '{print $3}' \
      | sort -V -r \
      | head -n 1 \
      || true
  )"
fi

if [[ -n "$latest_tag" ]]; then
  version="${latest_tag#build-}"
else
  version="$BASE_VERSION"
fi

if [[ "$next" == true ]]; then
  version="$(increment_version "$version")"
fi

printf '%s\n' "$version"
