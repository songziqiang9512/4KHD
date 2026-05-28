# 4KHD Task Playbooks

Use the smallest playbook that matches the user's request.

## Bug Fix

1. Identify the user-visible failure and likely module.
2. Search for the exact state path, callback, or UI action involved.
3. Compare with the closest stable implementation if an online module is involved.
4. Patch only the fault path.
5. Verify with build plus a targeted search or manual reasoning note.

## Code Review

1. Lead with findings, ordered by severity.
2. Use file and line references.
3. Prefer reproducible bugs over style comments.
4. Check stale async writes, cross-module leakage, route mismatch, missing cleanup, and UI state desync.
5. If no issues are found, say so and name remaining test gaps.

## Continue Development

1. Reconstruct current state from code and `git status`.
2. Ignore unrelated dirty files unless they affect the task.
3. Pick one unfinished item that is supported by current code and docs.
4. Implement end to end: code, docs if needed, verification.

## Shell Integration

1. Search for the module ID in `4KHD/App` and `4KHD/Shell`.
2. Check route matching, sidebar nodes, toolbar snapshot/actions, command validation, inspector refresh, and window title.
3. For new module cases, compile to catch non-exhaustive switches.
4. Avoid importing module internals into Shell.

## Shared Refactor

1. Prove there are at least two current call sites, or a real complexity reduction.
2. Move only generic AppKit/platform/service behavior.
3. Keep business names and site-specific logic in modules.
4. Build after moving files because Xcode file discovery and duplicate names can fail.

## Commit Preparation

1. Confirm the user asked for a commit.
2. Run `git status --short` and inspect staged/unstaged changes.
3. Do not stage unrelated user work.
4. Run verification appropriate to the diff.
5. Commit with a concise imperative message.
