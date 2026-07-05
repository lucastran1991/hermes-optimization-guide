# PM Progress Report — bootstrap-script-delegation-provisioning-scripts

Plan: `plans/260704-2106-bootstrap-script-delegation-provisioning-scripts/` | Status: pending → in-progress

## What ran

`/ck:cook @plans/260704-2106-bootstrap-script-delegation-provisioning-scripts/ --auto --parallel`. 6 phases, disjoint files per the plan's own ownership table → dispatched as 6 parallel `fullstack-developer` agents, foreground, single message.

## Delivered (all 6 phases)

| Phase | File(s) | State |
|---|---|---|
| 1 | `templates/systemd/hermes.service` (RWPaths widened), `scripts/vps-bootstrap-oci.sh` (+6c/6d) | authored, reviewed |
| 2 | `scripts/provision-hermes-delegation/0-gh-auth.sh` | authored, reviewed |
| 3 | `scripts/provision-hermes-delegation/1-claude-auth.sh` | authored, reviewed |
| 4 | `scripts/provision-hermes-delegation/2-ccs-profile.sh` | authored, reviewed, **1 critical fix** |
| 5 | `scripts/provision-hermes-delegation/3-ccs-reuse-bridge.sh` | authored, reviewed, 1 minor fix |
| 6 | `scripts/provision-hermes-delegation/4-merge-delegation-config.sh`, README.md, CHANGELOG.md | authored, reviewed, 2 minor fixes |

## Code review outcome

1 `code-reviewer` pass across the full changeset (not per-phase — full diff at once for cross-file consistency checks).

- **Critical (fixed):** `2-ccs-profile.sh` string-concatenated `--preset`/`--api-key` into a `bash -c` source → shell-command-injection (arbitrary code as hermes on a value containing a quote or `$(...)`). Fixed via env-var indirection; closure verified live with a harmless PoC.
- **High (fixed):** `skills/dev/coding-agent-delegate/SKILL.md` still said ClaudeKit isn't installed by `vps-bootstrap*.sh` — now false since Phase 1 added 6c/6d to the OCI variant. Corrected.
- **Medium (fixed):** `3-ccs-reuse-bridge.sh` copied credential files without asserting `chmod 600` — now added.
- **Low (fixed):** no charset gate on `--ccs-profile` in `4-merge-delegation-config.sh` (parity gap vs `3-ccs-reuse-bridge.sh`'s `--instance` gate) — added. CHANGELOG mischaracterized `0-gh-auth.sh` as device-flow (it's `--with-token`) — worded fix. Redundant nested `sudo` in `4-merge-delegation-config.sh` — removed.
- All plan-mandated findings (F2, F3, F6b, F8, F12, F13) verified correct, no regression.

## What's NOT done (by design, human-gated)

No live-host action was taken: no `deploy-systemd-units.sh` run, no `hermes.service` restart, no script executed with a real credential. The plan's own scope boundary treats these as operator/`[HUMAN]` steps — every phase file's Success Criteria list splits into artifact-level (satisfied) vs runtime-level (open) items; see each phase's new "Execution Status" section.

## Unresolved questions

- None on scope — live execution was always meant to be a separate, later, human-run step per the plan's design, not part of this cook session.
