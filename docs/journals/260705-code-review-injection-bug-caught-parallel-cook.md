# Code Review Caught Shell Injection After Parallel Cook Execution

**Date**: 2026-07-05 08:32
**Severity**: High
**Component**: bootstrap delegation provisioning scripts (`2-ccs-profile.sh`, `3-ccs-reuse-bridge.sh`, `4-merge-delegation-config.sh`)
**Status**: Resolved (artifacts fixed, awaiting live deployment)

## What Happened

Executed `/ck:cook plans/260704-2106-bootstrap-script-delegation-provisioning-scripts/ --auto --parallel` to implement the 6-phase provisioning plan, dispatching all phases to parallel `fullstack-developer` subagents simultaneously (justified by zero file-ownership overlap proven in the plan's own matrix). The mandatory code-review pass across the full changeset caught a **real unsafe interpolation vulnerability** that the plan's upstream 15 red-team findings (F1-F15) had completely missed.

## The Brutal Truth

The red-team pass is supposed to be comprehensive. Having 15 findings across 6 phases gave a false sense of safety. But the code reviewer traced data flow where the red team didn't: the `--preset` and `--api-key` user-supplied values were being string-concatenated directly into a `bash -c` source string in `2-ccs-profile.sh`, meaning a value containing a quote or `$(...)` would execute arbitrary code as the `hermes` user when the inner shell re-parsed it. This is a **fundamental injection bug**, not a nuance. The fact that red-team missed it feels like a gap in threat modeling — we enumerated implementation details (argv visibility, privilege escalation vectors) but didn't trace value taint through shell re-parsing. And the injection was only two lines of code away from the call site.

## Technical Details

**Vulnerable code** (`2-ccs-profile.sh`):
```bash
sudo -u hermes -i bash -c "ccs-profile ... --preset '$CCS_PRESET' --api-key '$CCS_API_KEY' ..."
```

Attack vector: a crafted value like `foo'; touch /tmp/pwn; echo 'bar` would:
1. Break the inner string
2. Execute `touch /tmp/pwn` as `hermes`
3. Resume the string

**Fix** (env-var indirection):
```bash
sudo -u hermes -i env CCS_PRESET="$CCS_PRESET" CCS_API_KEY="$CCS_API_KEY" bash -c 'ccs-profile ... --preset "$CCS_PRESET" --api-key "$CCS_API_KEY" ...'
```

**Verification**: Passed a harmless PoC value (`"; touch /tmp/pwn_poc; echo "`) through the fixed code path; confirmed the file was NOT created and the command executed safely (the value was treated as a literal string, not code).

## What We Tried

- Red-team pass: enumerated 15 findings pre-cook, missed this one
- Parallel cook: dispatched all 6 phases concurrently, no blocking
- Code review: single holistic pass across full changeset (caught the injection)
- Minor findings remediation: fixed 5 additional issues same-session

## Root Cause Analysis

1. **Red-team focus was too narrow**: F12 (mandating the `sudo -u hermes -i bash -c '<cmd>'` wrapper form) satisfied the constraint about privilege separation, but didn't verify safe interpolation *within* that form. Two different properties, both required.
2. **Value taint wasn't traced**: The path from user input (`--preset`, `--api-key` flags) to shell re-parsing wasn't explicitly modeled in threat scenarios.
3. **String concatenation is invisible in code review if you're skimming**: The vulnerability is a pattern match (user input + quote context + `bash -c`), not a typo. Easy to miss if you're reading for semantic correctness rather than injection surfaces.

## Lessons Learned

1. **Red teams need a data-flow pass**: Enumerate findings by category (privilege, visibility, injection surface, etc.) and ensure *all* user-controlled values are traced through *all* shell execution contexts, not just checked for existence.
2. **Safe wrapper form ≠ safe interpolation**: Using `sudo -u user -i bash -c` is good practice, but it's useless if the values inside are concatenated unsafely. Require env-var indirection or separate argument passing, never direct string concat into `bash -c`.
3. **Code review catches injection that design-review misses**: The red team was working from requirements and threat models; the code reviewer was reading actual shell syntax. Both are necessary.

## Next Steps

1. **Artifact status**: Phase files updated to `in-progress` with per-phase "Execution Status" notes. Injection fix verified on this host; awaiting operator sign-off before live deployment.
2. **Minor findings**: 5 secondary issues also fixed same-session:
   - Stale SKILL.md claim (said ClaudeKit isn't installed by vps-bootstrap — now false)
   - Missing `chmod 600` on credentials in `3-ccs-reuse-bridge.sh`
   - Missing charset validation on `--ccs-profile` in `4-merge-delegation-config.sh`
   - CHANGELOG wording (called `0-gh-auth.sh` mechanism "device-flow" vs. actual `--with-token`)
   - Redundant nested `sudo`
3. **Scope boundary held**: No live-host execution (no `deploy-systemd-units.sh`, no `hermes.service` restart, no real credentials used) — per plan's own explicit scope, not an oversight.
4. **Follow-up**: Before next red-team cycle, update threat model templates to include explicit "data-flow taint through shell execution contexts" row.
