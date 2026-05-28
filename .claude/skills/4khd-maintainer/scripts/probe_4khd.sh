#!/usr/bin/env bash
set -u

input_root="${1:-$(pwd)}"

if [[ -d "$input_root/4KHD.xcodeproj" ]]; then
  root="$input_root"
elif [[ -d "/Users/songziqiang/Documents/Development/4KHD/4KHD.xcodeproj" ]]; then
  root="/Users/songziqiang/Documents/Development/4KHD"
else
  echo "4KHD probe: unable to locate 4KHD.xcodeproj" >&2
  exit 2
fi

cd "$root" || exit 2

have_rg=1
command -v rg >/dev/null 2>&1 || have_rg=0

section() {
  printf '\n== %s ==\n' "$1"
}

section "Repository"
printf 'root: %s\n' "$root"
git branch --show-current 2>/dev/null | sed 's/^/branch: /' || true
git status --short 2>/dev/null || true

section "Top-level source layout"
find 4KHD -maxdepth 2 -type d | sort | sed -n '1,120p'

section "Module directories"
find 4KHD/Modules -maxdepth 1 -mindepth 1 -type d 2>/dev/null | sort | sed 's#^#- #'

section "WorkspaceModuleID"
if [[ "$have_rg" -eq 1 ]]; then
  rg -n "enum WorkspaceModuleID|case [A-Za-z0-9_]+" 4KHD/Shell/WorkspaceRoute.swift 2>/dev/null || true
else
  grep -nE "enum WorkspaceModuleID|case [A-Za-z0-9_]+" 4KHD/Shell/WorkspaceRoute.swift 2>/dev/null || true
fi

section "Known module switch surfaces"
for module_case in fourKHDGallery localLibrary missKon wallhaven; do
  printf '\n.%s\n' "$module_case"
  if [[ "$have_rg" -eq 1 ]]; then
    count=$(rg -n "case \\.$module_case" 4KHD/App 4KHD/Shell --glob '*.swift' 2>/dev/null | wc -l | tr -d ' ')
    printf 'case count: %s\n' "$count"
    rg -n "case \\.$module_case" 4KHD/App 4KHD/Shell --glob '*.swift' 2>/dev/null | sed -n '1,24p' || true
  else
    grep -RIn "case .$module_case" 4KHD/App 4KHD/Shell --include='*.swift' 2>/dev/null | sed -n '1,24p' || true
  fi
done

section "Toolbar snapshot cases"
if [[ "$have_rg" -eq 1 ]]; then
  rg -n "case \\.(gallery|local|missKon|wallhaven)\\(" 4KHD/App/WorkspaceToolbarContext.swift 4KHD/Shell/Toolbar/WorkspaceToolbarHost.swift 4KHD/Shell/WorkspaceCommandValidator.swift 2>/dev/null | sed -n '1,120p' || true
else
  grep -RInE "case \\.(gallery|local|missKon|wallhaven)\\(" 4KHD/App/WorkspaceToolbarContext.swift 4KHD/Shell/Toolbar/WorkspaceToolbarHost.swift 4KHD/Shell/WorkspaceCommandValidator.swift 2>/dev/null | sed -n '1,120p' || true
fi

section "Forbidden SwiftUI production APIs"
if [[ "$have_rg" -eq 1 ]]; then
  if rg -n "import SwiftUI|NSHosting|NSViewRepresentable|AnyView" 4KHD --glob '*.swift'; then
    printf 'status: FOUND forbidden API references\n'
  else
    printf 'status: none found\n'
  fi
else
  grep -RInE "import SwiftUI|NSHosting|NSViewRepresentable|AnyView" 4KHD --include='*.swift' || printf 'status: none found\n'
fi

section "Docs"
find docs -maxdepth 2 -type f -name '*.md' 2>/dev/null | sort || true
if [[ "$have_rg" -eq 1 ]]; then
  rg -n "TODO|TBD|deprecated|废弃|旧的|最近完成|已完成的工作|本轮|本次" AGENTS.md README.md docs --glob '*.md' 2>/dev/null || true
fi

section "Suggested verification"
printf '%s\n' \
  "xcodebuild -project 4KHD.xcodeproj -scheme 4KHD -configuration Debug -destination 'platform=macOS' build" \
  "rg \"import SwiftUI|NSHosting|NSViewRepresentable|AnyView\" 4KHD --glob '*.swift'" \
  "git diff --check"
