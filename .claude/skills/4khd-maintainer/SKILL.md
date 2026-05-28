---
name: 4khd-maintainer
description: Maintain and evolve the 4KHD macOS native AppKit image browser. Use when working in the 4KHD repository on Swift/AppKit code, online modules such as Gallery/MissKon/Wallhaven, Shell routing, Toolbar/Sidebar/Inspector integration, Shared-layer refactors, bug fixes, code review, build verification, documentation cleanup, or git handoff/commit preparation.
---

# 4KHD Maintainer

Use this skill as an operating procedure, not as a frozen project snapshot. Reconstruct the current project state from code, then use the project docs as hints.

## Start Every Task

1. Confirm the repository root. Prefer the user's current workspace; otherwise locate `4KHD.xcodeproj`.
2. Run `scripts/probe_4khd.sh <repo-root>` when available.
3. Read `AGENTS.md` and the newest `docs/ai-handover-*.md` only as fallible context.
4. Check `git status --short` before editing. Preserve unrelated user changes.
5. Choose the smallest playbook that fits the request. See `references/task-playbooks.md`.
6. Before editing, inspect the relevant code paths and state the intended edit surface.
7. Verify with commands matched to the change surface, then summarize changed files and residual risk.

## Stale Docs Protocol

Treat all docs as stale until the code confirms them.

- If docs conflict with source code, trust source code plus build/test results.
- If docs describe completed migration plans or round-by-round history, do not extend that pattern.
- When updating docs, keep durable operating facts and delete obsolete process history.
- If a doc claim matters to the task, validate it with `rg`, directory scans, project settings, or a build.

## Decision Tree

- **Bug fix or feature work:** read `references/task-playbooks.md`; inspect code first; make minimal edits; build if Swift changed.
- **Online module work:** read `references/online-module-risk-checklist.md`; compare against the most mature online module currently in code.
- **Shell, route, toolbar, sidebar, inspector:** use `rg "case \\.moduleID"` patterns and verify all switch surfaces.
- **Shared refactor:** read `references/architecture-guardrails.md`; only extract code used by at least two modules or code that clearly reduces current complexity.
- **Docs cleanup or handoff:** read `references/doc-maintenance.md`; prefer replacement and deletion over append-only changelogs.
- **Code review:** lead with concrete findings and file/line references; verify suspected issues against code paths.

## Stable Guardrails

- Production UI stays AppKit. Do not introduce `import SwiftUI`, `NSHostingController`, `NSViewRepresentable`, or `AnyView`.
- Keep boundaries: `App` assembles, `Shell` routes/layouts, `Shared` holds cross-module utilities, `Modules` hold business logic.
- Modules must not directly depend on other modules; share through `Shared` or stable app-level assembly.
- Prefer macOS system controls and AppKit behavior over custom drawing.
- Do not broaden a task into style cleanup, historical cleanup, or abstraction work unless it is required for the requested outcome.
- Only commit when the user asks for a commit or the active workflow explicitly requires it.

## Verification Menu

Use only the checks justified by the change.

```bash
# Full app build
xcodebuild -project 4KHD.xcodeproj -scheme 4KHD -configuration Debug -destination 'platform=macOS' build

# 0 SwiftUI production-code check
rg "import SwiftUI|NSHosting|NSViewRepresentable|AnyView" 4KHD --glob '*.swift'

# Switch-surface discovery for module integration
rg "case \\.missKon|case \\.fourKHDGallery|case \\.wallhaven" 4KHD/Shell 4KHD/App --glob '*.swift'

# Patch hygiene
git diff --check
```

## Rationalizations To Reject

- "The docs say it is true, so no need to inspect code."
- "This module looks similar enough, so one switch case is probably enough."
- "`host.contains(...)` is fine for domain filtering."
- "`lowercased()` indices can slice the original Swift string."
- "Put it in `Shared` now because another module might need it later."
- "This is docs-only, so stale links and duplicate handoffs do not matter."
