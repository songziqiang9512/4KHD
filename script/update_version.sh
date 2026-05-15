#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$script_dir/.." && pwd)"
# shellcheck source=/dev/null
source "$script_dir/version.env"

version="$("$script_dir/resolve_version.sh" "$@")"
build_number="${version//./}"
project_file="$repo_root/$XCODE_PROJECT/project.pbxproj"

if [[ ! -f "$project_file" ]]; then
  echo "Xcode project file not found: $project_file" >&2
  exit 1
fi

perl -0pi -e "s/MARKETING_VERSION = [^;]+;/MARKETING_VERSION = $version;/g; s/CURRENT_PROJECT_VERSION = [^;]+;/CURRENT_PROJECT_VERSION = $build_number;/g" "$project_file"

echo "$version"
