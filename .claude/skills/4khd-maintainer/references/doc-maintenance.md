# 4KHD Documentation Maintenance

Docs should reduce future work. Do not preserve history for its own sake.

## Keep

- Current architecture boundaries.
- Current module inventory, if verified from code.
- Durable project constraints and verification commands.
- Known risks that still affect implementation.
- Short handoff notes that help a new agent resume work.

## Remove Or Replace

- Round-by-round changelogs.
- Completed migration plans.
- Old handoffs superseded by a newer handoff.
- File counts, commit IDs, completion percentages, and status claims that go stale quickly.
- Duplicated lists already covered by `AGENTS.md` or README.

## Update Workflow

1. Scan docs for references to deleted files or obsolete plans.
2. Verify important status claims against source code.
3. Prefer concise replacement sections over append-only updates.
4. Run `git diff --check`.
5. For docs-only changes, do not run a full build unless the user asks or docs changed commands/configuration.
