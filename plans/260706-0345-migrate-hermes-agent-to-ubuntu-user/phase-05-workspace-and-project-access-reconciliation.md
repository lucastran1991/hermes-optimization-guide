---
phase: 5
title: "Workspace and Project Access Reconciliation"
status: complete
priority: P2
effort: "30m"
dependencies: [3]
---

# Phase 5: Workspace and Project Access Reconciliation

## Overview

Point Hermes's workspace references at ubuntu's existing `/home/ubuntu/workspace/` clones
instead of hermes's own (stale, redundant) copies. Research found `kitchen` is identical
commit on both sides, and `nfi` is out of date on hermes's side but has a clean working tree
(no uncommitted changes, no stashes) — so there is nothing to merge, only paths to repoint.

## Key Insights

| Repo | hermes commit | ubuntu commit | Uncommitted work on hermes side? | Action |
|---|---|---|---|---|
| `kitchen` | `1eb6f72` | `1eb6f72` (same) | None found | None needed — already in sync |
| `nfi` | `1aa032f6` | `9201b4a` (ahead) | None found (`git status --short` empty, no stashes) | Use ubuntu's copy; hermes's stale copy is discarded with the rest of `/home/hermes` at cleanup |

Both repos use different remote URL variants per user (`https://` on hermes's side,
`git@`/SSH on ubuntu's side) — same repos, just different clone protocol. Not a conflict.

**Critical dependency on Phase 6 (red-team finding, corroborated independently by 3 of 4
reviewers):** ownership alone does not grant write access under systemd sandboxing.
`hermes.service`'s current `ReadWritePaths=/home/hermes/.hermes /home/hermes/.ccs /tmp` never
included the workspace directory — this is a **live, already-reproduced bug**
(`plans/260705-1752-ccs-delegation-timeout-progress-tracking-fix/phase-03-live-host-verification.md:544`
shows `Read-only file system` errors from delegated writes into `/home/hermes/workspace/nfi`
today). A straight path-swap of the same unit shape for ubuntu (`ReadWritePaths=/home/ubuntu/.hermes
/home/ubuntu/.ccs /tmp`) reproduces the identical bug in the new location — `ProtectHome`-style
sandboxing makes everything else under `/home` read-only regardless of Unix ownership. This
plan's earlier draft of Phase 6 had exactly this gap; **Phase 6 has been corrected to add
`/home/ubuntu/workspace` to `ReadWritePaths=`** — this phase's step 4 verification only means
something once that fix is actually in place.

## Related Code Files

- Modify (host): `/home/ubuntu/.hermes/config.yaml` and/or `SOUL.md` if either hardcodes a workspace path (check in step 1)
- No repo files in `hermes-optimization-guide` itself are touched.

## Implementation Steps

1. **[AGENT]** Confirm no workspace path is hardcoded anywhere already-restored (this should already be clean per Phase 3 step 6, this is a targeted re-check scoped to workspace paths specifically):
   ```bash
   grep -rn "workspace" /home/ubuntu/.hermes/config.yaml /home/ubuntu/.hermes/SOUL.md
   ```
   Fix any `/home/hermes/workspace/...` references found to `/home/ubuntu/workspace/...`.

2. **[AGENT]** Diff the two workspace directories for anything unique to hermes's copy that isn't in ubuntu's (beyond the two known repos):
   ```bash
   diff <(sudo -u hermes bash -c 'ls ~/workspace/') <(ls /home/ubuntu/workspace/)
   ```
   If hermes's `workspace/` has a directory ubuntu's doesn't, investigate it individually before
   assuming it's safe to drop at cleanup — it may be a project Hermes created independently
   (e.g., from a delegated task) that was never cloned under ubuntu.

3. **[AGENT]** No copy/merge needed for `kitchen`/`nfi` themselves (confirmed clean, ubuntu's copies win) — this step is a no-op by design, documented here so it isn't mistaken for an oversight.

4. **[AGENT]** Once the new ubuntu-based Hermes instance is live (post-Phase 6), confirm it can
   actually write to the shared workspace **from inside the sandboxed service context**, not
   just confirm ownership from a bare shell (red-team finding: an `ls -la` ownership check
   passes even when `ProtectHome`/`ReadWritePaths` sandboxing would reject the write — Unix
   ownership and systemd sandbox permissions are independent layers):
   ```bash
   sudo systemd-run --uid=ubuntu --gid=ubuntu -p ReadWritePaths=/home/ubuntu/.hermes /home/ubuntu/.ccs /home/ubuntu/workspace /tmp -p ProtectHome=read-only --pipe --wait \
     bash -c 'touch /home/ubuntu/workspace/nfi/.hermes-migration-write-test && rm /home/ubuntu/workspace/nfi/.hermes-migration-write-test && echo WRITE_OK'
   ```
   Must print `WRITE_OK`, not `Read-only file system`. This exercises the exact sandboxing
   properties the real `hermes.service` unit uses (see Phase 6), not a bare unsandboxed shell.

## Success Criteria

- [x] No `/home/hermes` path references remain in `/home/ubuntu/.hermes/config.yaml` or `SOUL.md` related to workspace/project paths. Only hit was `docker_mount_cwd_to_workspace: false` — a config key name, not a path.
- [x] `diff` of the two `workspace/` directory listings reviewed. hermes's workspace has exactly `kitchen`+`nfi` (matches plan's Key Insights), both already present under ubuntu's workspace (which has many more repos hermes doesn't have — expected, not a gap). Zero hermes-unique directories found — nothing to migrate or account for.
- [x] Post-cutover (Phase 6 done), the sandboxed write test prints `WRITE_OK` against `nfi` (re-verified again in Phase 7 in production, not just Stage A rehearsal).
- [x] Phase 6's `ReadWritePaths=` for both units explicitly includes `/home/ubuntu/workspace` — confirmed in installed unit files.

## Risk Assessment

- **Low risk in this phase's own actions** — no destructive action here; it's a verification + path-reference sweep. The one direct risk is silently discarding a hermes-unique workspace directory that turns out to matter (step 2 exists specifically to catch that before Phase 8 makes it unrecoverable).
- **Real risk lives in Phase 6, not here**: this phase's success criteria are only meaningful if Phase 6's systemd unit actually grants workspace write access — see Key Insights above. Do not mark this phase's success criteria met by an ownership check alone.
