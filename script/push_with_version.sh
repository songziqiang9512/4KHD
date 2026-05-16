#!/usr/bin/env bash
set -euo pipefail

repo_root="$(git rev-parse --show-toplevel)"
cd "$repo_root"

current_branch="$(git symbolic-ref --quiet --short HEAD)"
remote_name="${1:-origin}"
shift || true

if git rev-parse --verify --quiet "@{upstream}" >/dev/null; then
  ahead_count="$(git rev-list --count "@{upstream}..HEAD")"
else
  ahead_count=1
fi

if [[ "$ahead_count" != "0" ]]; then
  version="$(script/update_version.sh --next)"
  project_file="4KHD.xcodeproj/project.pbxproj"
  if ! git diff --quiet -- "$project_file"; then
    git add "$project_file"
    git commit -m "Bump version to $version"
  fi
fi

SKIP_VERSION_PREPUSH=1 git push "$remote_name" "$current_branch" "$@"
