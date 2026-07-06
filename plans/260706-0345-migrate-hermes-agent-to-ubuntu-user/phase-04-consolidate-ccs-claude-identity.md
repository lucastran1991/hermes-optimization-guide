---
phase: 4
title: "Consolidate CCS/Claude Identity"
status: complete
priority: P1
effort: "1h"
dependencies: [3]
---

# Phase 4: Consolidate CCS/Claude Identity

## Overview

Move Hermes's real, working `ccs-hermes` CCS profile from `/home/hermes/.ccs/instances/ccs-hermes/`
to `/home/ubuntu/.ccs/instances/ccs-hermes/`, merge its `accounts:` config entry into ubuntu's
`~/.ccs/config.yaml`, and remove the stale placeholder that's been sitting in ubuntu's config
(`ANTHROPIC_AUTH_TOKEN: "x"`). This is the "reuse the existing `ccs-hermes` bridge entry"
decision — the profile keeps its own identity (separate from `ken`/`luan`/`lucas`), it just
becomes a native ubuntu profile instead of a cross-user bridge.

**Do not** copy `hermes`'s `~/.ccs/instances/{ken,luan,lucas}/` directories over. Those are
verbatim copies of ubuntu's own credentials (confirmed via research: different inode, same
`claudeAiOauth` structure, different token hash than ubuntu's originals) — a security-relevant
duplication this migration should retire, not relocate. Ubuntu already has the originals.
They'll be destroyed for good with the rest of `/home/hermes` in Phase 8.

## Key Insights

- `ccs-hermes` is confirmed **functional today**: created 2026-07-05, last used same day,
  `ccs ccs-hermes -p "echo test"` returns a real Claude response. This is the identity to
  preserve, not recreate.
- Ubuntu's `~/.ccs/config.yaml` currently defines `ccs-hermes` under a `profiles:` block (API-key
  type, unpopulated). Hermes's `~/.ccs/config.yaml` defines it under an `accounts:` block
  (OAuth-based, populated, working). These are different schema shapes for the same profile
  name — the `accounts:` version is the one to keep.
- `/home/ubuntu/.ccs/ccs-hermes.settings.json` (the placeholder file) is unused dead weight —
  confirmed nothing reads it once the `accounts:` entry exists.

## Related Code Files

- Move (host): `/home/hermes/.ccs/instances/ccs-hermes/` → `/home/ubuntu/.ccs/instances/ccs-hermes/`
- Modify (host): `/home/ubuntu/.ccs/config.yaml` (remove stale `profiles.ccs-hermes`, add `accounts.ccs-hermes` entry)
- Delete (host): `/home/ubuntu/.ccs/ccs-hermes.settings.json`

## Implementation Steps

1. **[AGENT]** Copy (not yet move — keep hermes's copy until verified) the real profile instance:
   ```bash
   sudo cp -a /home/hermes/.ccs/instances/ccs-hermes /home/ubuntu/.ccs/instances/ccs-hermes
   sudo chown -R ubuntu:ubuntu /home/ubuntu/.ccs/instances/ccs-hermes
   chmod 700 /home/ubuntu/.ccs/instances/ccs-hermes
   chmod 600 /home/ubuntu/.ccs/instances/ccs-hermes/.credentials.json
   ```

2. **[AGENT]** Extract the working `accounts:` entry for `ccs-hermes` from hermes's config:
   ```bash
   sudo -u hermes bash -c "cat ~/.ccs/config.yaml" > /tmp/hermes-ccs-config.yaml
   grep -n -A15 "^  ccs-hermes:" /tmp/hermes-ccs-config.yaml   # find the exact accounts.ccs-hermes block, note line range
   ```

3. **[HUMAN]** Edit `/home/ubuntu/.ccs/config.yaml`:
   - Remove the existing `profiles:` → `ccs-hermes:` block (the stale placeholder, ~line 29-31 per planning-time research; confirm actual line number since the file may have changed).
   - Insert the real `accounts:` → `ccs-hermes:` block extracted in step 2 into ubuntu's `accounts:` section (create the `accounts:` top-level key if ubuntu's config doesn't already have one — check first: `grep -n "^accounts:" /home/ubuntu/.ccs/config.yaml`).
   - Validate YAML **syntax** after editing: `python3 -c "import yaml; yaml.safe_load(open('/home/ubuntu/.ccs/config.yaml'))" && echo VALID`
   - Validate YAML **structure** too — syntax validity alone doesn't catch a mis-indented paste
     silently nesting `ccs-hermes` under the wrong parent, e.g. under `ken`/`luan`/`lucas`
     instead of as a sibling (red-team finding). Confirm the key path and siblings explicitly:
     ```bash
     python3 -c "
     import yaml
     c = yaml.safe_load(open('/home/ubuntu/.ccs/config.yaml'))
     assert 'ccs-hermes' in c.get('accounts', {}), 'ccs-hermes missing from accounts'
     assert set(['ken','luan','lucas']).issubset(c.get('accounts', {}).keys()) or True  # adjust to actual pre-existing key names
     print('accounts top-level keys:', list(c.get('accounts', {}).keys()))
     "
     ```
     Confirm the printed key list shows `ccs-hermes` as a **sibling** of `ken`/`luan`/`lucas`
     (or wherever they actually live in ubuntu's schema — check first, don't assume), not nested
     underneath one of them.

4. **[AGENT]** Delete the now-unused placeholder settings file:
   ```bash
   rm /home/ubuntu/.ccs/ccs-hermes.settings.json
   ```

5. **[AGENT]** Smoke test — same gate the original provisioning script used:
   ```bash
   ccs ccs-hermes -p "echo ok" --output-format json
   ```
   Must exit 0 with a real JSON response (not an auth error). This is the definitive test that
   the moved credential + merged config actually work together as ubuntu.

6. **[AGENT]** Do **NOT** delete hermes's copy here (changed by red-team: the original version
   of this step deleted `/home/hermes/.ccs/instances/ccs-hermes` immediately after step 5's
   smoke test, which directly contradicted Phase 7/plan.md's claim that "Phases 1-6 are
   non-destructive to `/home/hermes`" — a rollback invoked during the 48h window would restart
   `hermes.service` as user `hermes` with its CCS identity already broken, meaning rollback
   would not actually restore prior behavior). Instead, leave hermes's copy in place untouched;
   deletion is now Phase 8's job, after the 48h rollback window has actually closed:
   ```bash
   # Intentionally no deletion here. hermes's ~/.ccs/instances/ccs-hermes/ and its
   # ~/.ccs/config.yaml accounts.ccs-hermes entry stay live and untouched until Phase 8.
   # The credential now exists in two places (hermes's original + ubuntu's copy) for the
   # duration of the rollback window ONLY — this is intentional overlap for rollback safety,
   # not the same as the ken/luan/lucas duplication pattern this migration is retiring (that
   # duplication was permanent and cross-identity; this one is temporary and same-identity).
   ```

## Success Criteria

- [x] `ccs ccs-hermes -p "echo ok" --output-format json` succeeds as `ubuntu`, using the moved credential — real response, `is_error:false`, `result:"ok"`, cost $0.283.
- [x] `/home/ubuntu/.ccs/config.yaml` has exactly one `ccs-hermes` entry (under `accounts:`), no leftover `profiles.ccs-hermes` placeholder (`profiles: {}` now).
- [x] `/home/ubuntu/.ccs/ccs-hermes.settings.json` no longer exists.
- [x] `/home/hermes/.ccs/instances/ccs-hermes/` and its config entry deliberately left in place (not deleted) until Phase 8.
- [x] Structural YAML check confirms `ccs-hermes` sits as a sibling of `lucas`/`ken`/`luan` — verified: `accounts top-level keys: ['lucas', 'ken', 'luan', 'ccs-hermes']`.
- [x] No copies of `ken`/`luan`/`lucas` credentials touched — smoke-tested `ccs ken -p "echo ok"` afterward, `is_error:false`, confirms human's own daily-driver profile undisturbed.
- [x] **Gap found and fixed, not in original plan**: the copied `ccs-hermes` instance dir had 4 symlinks (`agents`, `commands`, `settings.json`, `skills`) pointing at `/home/hermes/.ccs/shared/...` — `/home/hermes` is mode `750 hermes:hermes`, so ubuntu cannot traverse into it at all; these were dead symlinks immediately after the copy. Relinked to `/home/ubuntu/.ccs/shared/...`, matching the exact pattern already used by ubuntu's own `ken`/`luan`/`lucas` instances (confirmed identical pattern before applying). Verified readable post-fix.

## Risk Assessment

- **Medium-high risk**: this touches ubuntu's own `~/.ccs/config.yaml`, which also serves `ken`/`luan`/`lucas` — a malformed edit here could break the human's own daily-driver CCS profiles, not just Hermes. Mitigate: back up the file before editing (`cp ~/.ccs/config.yaml ~/.ccs/config.yaml.pre-phase4.bak`), validate YAML syntax after editing (step 3), and smoke-test `ccs ken -p "echo ok"` afterward too, to confirm the human's own profiles weren't disturbed.
- Order matters: copy-then-verify-then-leave-source-until-Phase-8 (steps 1→5→6) — red-team
  correction: never delete hermes's copy at all during Phases 1-7, since Phase 7's rollback
  procedure depends on it still existing and working if a rollback is invoked.

## Security Considerations

- This phase is the direct fix for the **permanent, cross-identity** credential-duplication
  finding from research (hermes holding real copies of ubuntu's `ken`/`luan`/`lucas` OAuth
  tokens). After this phase, `ccs-hermes` exists in two places **temporarily** (hermes's
  original + ubuntu's copy, both same-identity, both functional) only for the duration of the
  Phase 7 rollback window — this is intentional and reviewed, not a new instance of the
  cross-identity duplication pattern this migration is retiring. `ken`/`luan`/`lucas` credential
  copies under `/home/hermes` are untouched here but will be permanently destroyed in Phase 8
  along with the rest of the old home.
