---
phase: 4
title: "CI Action SHA Pin"
status: completed
effort: "0.25h"
---

# Phase 4: CI Action SHA Pin

## Context Links

- Research (ground truth): `research/researcher-real-hermes-schema-and-fix-verification-report.md` (§ "LOW #6")
- Scan finding: `plans/reports/security-scan-260703-1005-full-repo-secrets-code-config-audit-report.md` (LOW #6)

## Overview

**Priority:** LOW (finding #6). **Status:** Pending.

`.github/workflows/ci.yml:16` pins the third-party action `gaurav-nelson/github-action-markdown-link-check` by the mutable tag `@v1`. A re-tag of `v1` could silently change behavior. Pin to the commit SHA `5c5dfc0ac2e225883c0e5f03a85311ec2830d368` (research-verified + red-team-corrected 2026-07-03 — see Key Insights) with a trailing `# v1` comment (standard supply-chain-pin style).

## Key Insights

- Low impact: workflow uses `pull_request` (not `pull_request_target`), references no secrets, has no elevated `permissions:` — but SHA-pinning is the standard hardening for third-party actions.
- `actions/checkout@v4` and `actions/setup-python@v5` are first-party GitHub actions — out of scope (finding names only the third-party action).
- **Annotated tag — two SHAs exist, use the right one.** `v1` on this repo is an annotated tag, so `git ls-remote 'refs/tags/v1*'` returns two lines: the tag OBJECT's own SHA (`499c1e7f3637c131334fa8e937c45144f79d72d2`, bare `refs/tags/v1`) and the COMMIT it points to (`5c5dfc0ac2e225883c0e5f03a85311ec2830d368`, `refs/tags/v1^{}`). The original research pass transcribed the tag-object SHA by mistake; red-team review caught it via the GitHub API (`GET /git/tags/499c1e7f...` → `type: commit`, `sha: 5c5dfc0a...`; `GET /git/commits/499c1e7f...` → `404`). **Use `5c5dfc0ac2e225883c0e5f03a85311ec2830d368` — the peeled commit.** A tag-object pin is reachable only via the `v1` ref (GC-eligible if that ref is ever deleted/retagged) and isn't recognized by SHA-audit tooling (Dependabot, `pin-github-action`, OpenSSF Scorecard), which resolves via the commits API.

## Requirements

**Functional**
- The markdown-link-check action is referenced by immutable commit SHA + `# v1` comment.

**Non-functional**
- `ci.yml` remains valid YAML.

## Architecture

No behavioral change — same action version, immutable reference. Trust anchor shifts from a mutable tag ref to a content-addressed commit SHA.

Change (line ~16):

```yaml
        uses: gaurav-nelson/github-action-markdown-link-check@5c5dfc0ac2e225883c0e5f03a85311ec2830d368 # v1
```

(from `uses: gaurav-nelson/github-action-markdown-link-check@v1`)

## Related Code Files

**Modify:**
- `.github/workflows/ci.yml` — `uses:` line ~16 only. Leave `actions/checkout`, `actions/setup-python`, and the yamllint job untouched.

**Create / Delete:** none.

## Implementation Steps

### Tests Before (baseline)

```sh
grep -n 'markdown-link-check@' .github/workflows/ci.yml     # expect: ...@v1
grep -c 'markdown-link-check@v1' .github/workflows/ci.yml   # expect 1
```

### Refactor

1. Replace `@v1` with `@5c5dfc0ac2e225883c0e5f03a85311ec2830d368 # v1` on the `uses:` line for `gaurav-nelson/github-action-markdown-link-check`.

### Tests After

```sh
grep -c 'markdown-link-check@5c5dfc0ac2e225883c0e5f03a85311ec2830d368' .github/workflows/ci.yml    # expect 1
grep -Ec 'markdown-link-check@v1( |$)' .github/workflows/ci.yml                                    # expect 0
yamllint -c .github/yamllint.yml .github/workflows/ci.yml                                          # valid YAML
# One-time SHA authenticity re-check. IMPORTANT: v1 is an ANNOTATED tag — this
# prints TWO lines. Use the `refs/tags/v1^{}` (peeled) line's SHA, NOT the bare
# `refs/tags/v1` line — the bare line is the tag object, not the commit.
git ls-remote https://github.com/gaurav-nelson/github-action-markdown-link-check.git 'refs/tags/v1*'
```

### Regression Gate

```sh
grep -q 'markdown-link-check@5c5dfc0ac2e225883c0e5f03a85311ec2830d368 # v1' .github/workflows/ci.yml \
  && test "$(grep -Ec 'markdown-link-check@v1( |$)' .github/workflows/ci.yml)" = "0" \
  && yamllint -c .github/yamllint.yml .github/workflows/ci.yml \
  && echo "PHASE 4 GATE PASS"
```

## Todo List

- [x] Pin action to SHA `5c5dfc0a…` (the peeled COMMIT sha, not the tag-object sha `499c1e7f…`) with `# v1` comment
- [x] Confirm no bare `@v1` remains
- [x] yamllint `ci.yml` valid
- [x] Run Regression Gate → `PHASE 4 GATE PASS`

## Success Criteria

- Action referenced by the exact SHA + `# v1` comment; no mutable-tag reference remains.
- `ci.yml` is valid YAML; the link-check job still runs on PRs.

## Risk Assessment

| Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|
| SHA transcription typo | Low | Med | Gate greps the full 40-char SHA literal; CI run confirms the action resolves. |
| Pinning the tag-object SHA instead of the commit SHA (already happened once in this plan's research — see Key Insights) | Low (now corrected) | Med | Gate greps for the specific peeled SHA `5c5dfc0a…`; if re-deriving in the future, always read the `^{}`-suffixed line from `git ls-remote` on an annotated tag, never the bare tag line. |
| Future need to bump `v1` | Low | Low | `# v1` comment records the human-readable tag for the next reviewer; re-pin on upgrade. |

## Security Considerations

- Removes a supply-chain surface: a compromised/re-tagged `v1` can no longer alter CI behavior silently. Content-addressed pin is the accepted hardening.
- No secrets in this workflow; blast radius already low, so this is defense-in-depth.

## Next Steps

- Fully independent file. No coordination needed.
