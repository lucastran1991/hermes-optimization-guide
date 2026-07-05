---
name: opt-vs-workspace-clone-drift-on-oci-host
description: lucas-oracle-instance has two independent git clones of this repo — /opt (bootstrap-canonical, can be stale) vs /home/ubuntu/workspace (dev, ahead). Any plan/script assuming one repo location is wrong.
metadata:
  type: project
---

On the live OCI host (`lucas-oracle-instance`), this repo exists in **two
independent git clones** that can and do diverge:

- `/opt/hermes-optimization-guide` — the **bootstrap-canonical** location.
  `scripts/vps-bootstrap.sh` / `-oci.sh` hardcode `GUIDE_DIR=/opt/hermes-optimization-guide`,
  clone/`git pull --ff-only` it, and it's the source for the live
  `~hermes/.hermes/skills/*` symlinks and `/etc/systemd/system/*.service`
  installs during a bootstrap run. No cron/timer keeps it updated between
  bootstrap runs — it silently goes stale.
- `/home/ubuntu/workspace/hermes-optimization-guide` — the dev/session clone
  (`ubuntu` user, this repo's actual git remote `lucastran1991/hermes-optimization-guide`),
  where planning/coding sessions actually happen. Routinely ahead of `/opt`.

**Why:** found 2026-07-03 reviewing `plans/260703-1738-fix-urgent-hermes-delegation-issues/`
(the seccomp-SIGSYS P0 fix plan). `/opt` was 2 days + several commits stale —
missing the seccomp fix commit (`c9631fc`) entirely and the whole
`coding-agent-delegate` skill (confirmed: `grep sched_setscheduler
/opt/.../templates/systemd/hermes.service` = no match; `ls
/opt/.../skills/dev/` lacks `coding-agent-delegate`; live `~hermes/.hermes/skills/`
has zero trace of it despite the other 3 `skills/dev/*` skills being correctly
symlinked from `/opt`). A new "deploy-drift-prevention" script that diffs
`templates/systemd/*` against the live unit and auto-installs+restarts on any
diff would, if ever run from `/opt` (the more discoverable, "official" path),
redeploy the stale pre-fix unit and reintroduce the bug it was meant to
prevent.

**How to apply:** when reviewing any plan/script that (a) deploys systemd
units, (b) symlinks/installs skills, or (c) otherwise assumes "the repo" is a
single location on this host — check `git -C /opt/hermes-optimization-guide
log -1` vs the workspace clone's HEAD before trusting either as
authoritative. Don't assume a fix "landed" on the host just because it's
committed in the workspace clone; verify the bootstrap-canonical `/opt` copy
independently. Related: [[skill-doc-vs-template-drift]] — same drift class,
different mechanism (guide-chapter prose vs. a whole stale clone).
