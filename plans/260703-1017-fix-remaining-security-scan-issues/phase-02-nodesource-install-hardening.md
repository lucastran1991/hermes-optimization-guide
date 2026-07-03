---
phase: 2
title: "NodeSource Install Hardening"
status: completed
effort: "0.5h"
---

# Phase 2: NodeSource Install Hardening

## Context Links

- Research (ground truth): `research/researcher-real-hermes-schema-and-fix-verification-report.md` (§ "MEDIUM #3")
- Scan finding: `plans/reports/security-scan-260703-1005-full-repo-secrets-code-config-audit-report.md` (MEDIUM #3)
- Upstream method verified against: NodeSource wiki `github.com/nodesource/distributions/wiki/Repository-Manual-Installation` (fetched 2026-07-03)

## Overview

**Priority:** MEDIUM (finding #3). **Status:** Pending.

Both bootstrap scripts install Node.js via `curl -fsSL https://deb.nodesource.com/setup_20.x | bash -`, run as root — a remote-script-execution-as-root pattern (host/TLS compromise → root RCE on the operator box). Replace that single line in each script with the verified manual GPG-key + signed-apt-source method, styled to match the Caddy install pattern already present in the same file.

## Key Insights

- **Only the NodeSource `curl|bash` line is in scope.** The Caddy gpg-key line in the same files (`curl … gpg.key | gpg --dearmor -o …`) is already the safe pattern (signed apt repo, no remote script exec) — do NOT touch it.
- `curl`, `ca-certificates`, `gnupg` are already installed by the earlier `apt-get install` prereq block in both scripts → **no new package deps**.
- Scripts run as root and use `apt-get -qq` with no `sudo` → the replacement must drop the wiki's `sudo` prefixes and mirror the existing Caddy `/usr/share/keyrings/…` style (not the wiki's `/etc/apt/keyrings`).
- vps-bootstrap-oci.sh has its Caddy block commented out, but its NodeSource line (~68) is active and in scope.

## Requirements

**Functional**
- No `curl | bash` remote script execution for Node install in either script.
- Node 20 installed from a GPG-signed apt source, key pinned to a local keyring.

**Non-functional**
- Replacement style matches the sibling Caddy block for readability.
- Scripts remain syntactically valid (`bash -n`).

## Architecture

Old data flow: `curl setup_20.x | bash -` → downloads + executes an arbitrary remote shell script as root (adds repo AND runs whatever else the script contains). New flow: fetch only the **static GPG public key** → dearmor to a local keyring → write a `signed-by=` apt source line → `apt-get update && install nodejs`. Trust anchor becomes the pinned key; no remote code executes.

Recommended replacement (Caddy-style one-line apt source; functionally equivalent to the wiki's deb822 `.sources` form):

```sh
  curl -fsSL https://deb.nodesource.com/gpgkey/nodesource-repo.gpg.key | \
    gpg --dearmor -o /usr/share/keyrings/nodesource.gpg
  echo "deb [signed-by=/usr/share/keyrings/nodesource.gpg] \
    https://deb.nodesource.com/node_20.x nodistro main" \
    > /etc/apt/sources.list.d/nodesource.list
  apt-get update -qq
  apt-get install -y -qq nodejs
```

This replaces the line `curl -fsSL https://deb.nodesource.com/setup_20.x | bash -` (the following `apt-get install -y -qq nodejs` line is folded into the block above).

## Related Code Files

**Modify:**
- `scripts/vps-bootstrap.sh` — NodeSource line ~55 (inside the `if ! command -v node` block ~53-57). Leave Caddy block ~62-71 untouched.
- `scripts/vps-bootstrap-oci.sh` — NodeSource line ~68 (inside the `if ! command -v node` block ~66-70).

**Create / Delete:** none.

## Implementation Steps

### Tests Before (baseline)

```sh
grep -c 'setup_20.x' scripts/vps-bootstrap.sh scripts/vps-bootstrap-oci.sh   # expect 1 each
grep -c 'cloudsmith.io/public/caddy' scripts/vps-bootstrap.sh                # record (must stay same after)
bash -n scripts/vps-bootstrap.sh && bash -n scripts/vps-bootstrap-oci.sh     # start green
```

### Refactor

1. In `vps-bootstrap.sh`, replace the `curl … setup_20.x | bash -` line (and its trailing `apt-get install nodejs`) with the recommended block above.
2. Repeat identically in `vps-bootstrap-oci.sh`.
3. Do not add `sudo`, do not add package installs (prereqs already present), do not alter the Caddy block.

### Tests After

```sh
grep -c 'setup_20.x' scripts/vps-bootstrap.sh scripts/vps-bootstrap-oci.sh          # expect 0 each
grep -c 'nodesource.gpg' scripts/vps-bootstrap.sh scripts/vps-bootstrap-oci.sh      # expect >=1 each
grep -c 'deb.nodesource.com/node_20.x' scripts/vps-bootstrap.sh scripts/vps-bootstrap-oci.sh  # expect >=1 each
bash -n scripts/vps-bootstrap.sh && bash -n scripts/vps-bootstrap-oci.sh            # still valid
```

### Regression Gate

Red-team correction (2026-07-03, reproduced live): the original gate's positive assertions only checked `vps-bootstrap.sh`, so a no-op/broken edit to `vps-bootstrap-oci.sh` still printed PASS. Both positive assertions must be duplicated per-file:

```sh
bash -n scripts/vps-bootstrap.sh && bash -n scripts/vps-bootstrap-oci.sh \
  && test "$(grep -c 'setup_20.x' scripts/vps-bootstrap.sh scripts/vps-bootstrap-oci.sh | awk -F: '{s+=$2} END{print s}')" = "0" \
  && grep -q 'signed-by=/usr/share/keyrings/nodesource.gpg' scripts/vps-bootstrap.sh \
  && grep -q 'signed-by=/usr/share/keyrings/nodesource.gpg' scripts/vps-bootstrap-oci.sh \
  && grep -q 'cloudsmith.io/public/caddy' scripts/vps-bootstrap.sh \
  && echo "PHASE 2 GATE PASS"
```

## Todo List

- [x] vps-bootstrap.sh: replace NodeSource `curl|bash` with GPG+apt-source block
- [x] vps-bootstrap-oci.sh: same replacement
- [x] Confirm Caddy block untouched in vps-bootstrap.sh
- [x] Run Regression Gate → `PHASE 2 GATE PASS`

## Success Criteria

- Zero `setup_20.x | bash` occurrences; both scripts install Node from a signed apt source.
- Caddy block byte-identical to before.
- `bash -n` clean on both.

## Risk Assessment

| Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|
| Wrong suite/component breaks `apt-get update` | Low | Med | Use verified upstream values (`node_20.x nodistro main`); tested form from NodeSource wiki. |
| Accidentally editing the Caddy line | Low | Med | Gate asserts Caddy line still present; scope edit to the `node` `if` block only. |
| Keyring path collides with Caddy's | Low | Low | Distinct filename `nodesource.gpg` vs `caddy-stable-archive-keyring.gpg`. |
| Regression gate only checks `vps-bootstrap.sh`, misses a broken/no-op fix in `vps-bootstrap-oci.sh` | Confirmed by red-team reproduction (2026-07-03) | High (silent Node-install failure on every OCI deploy) | Gate now duplicates the `nodesource.gpg` assertion for `vps-bootstrap-oci.sh` explicitly. |

## Security Considerations

- Eliminates remote-code-execution-as-root; trust reduced to a pinned, dearmored GPG key + signed repo (same model as Caddy).
- No secrets involved. Key fetched over TLS from the official NodeSource host.

## Next Steps

- Fully independent — no shared files with any other phase. Can run first / in parallel.
