# Plan: OCI-specific vps-bootstrap variant

**Status:** Done
**Mode:** auto, parallel (per `--auto --parallel`)

## Context

Prior security-scan on this OCI host (see `plans/reports/security-scan-260702-0407-scripts-directory-report.md` and chat history) found `scripts/vps-bootstrap.sh` unsafe to run as-is here because this box is a live, shared dev/agent host, not a fresh throwaway VPS:
- Tailscale-networked (100.92.67.9 / fd7a:... ULA), current SSH session itself rides Tailscale.
- `cloudflared` tunnel already handles ingress (127.0.0.1:20242) — no public 80/443 exposure model.
- Postgres, Docker, containerd, and several dev/agent processes listen on non-standard ports (3001, 8723, 34375, 35295, 35329, 41269, 43684).
- UFW currently inactive, iptables empty.

Conflicting sections in the original script:
- **Section 3 (Caddy install)** + **Section 9 (Caddy reference config)**: assumes public-IP + Let's Encrypt HTTP-01 ingress. This host uses `cloudflared` instead — Caddy would be dead weight.
- **Section 10 (UFW reset + default-deny + enable)**: would firewall off every non-22/80/443 port host-wide, breaking the Tailscale-reachable dev/agent services listed above. Firewalling should stay at the OCI Security List / NSG + Tailscale ACL layer for this host, not local UFW.

Everything else (hermes user, Node.js, guide clone, Hermes installer, skill symlinks, config/.env stubs, systemd units, fail2ban, unattended-upgrades) is unaffected and kept.

## Requirements

1. **Output:** new file `scripts/vps-bootstrap-oci.sh` — a variant of `vps-bootstrap.sh` for this specific OCI/Tailscale/cloudflared setup.
2. **Acceptance criteria:**
   - Caddy sections (3, 9) commented out with a one-line reason, not deleted (so the reference stays visible for someone who *does* want Caddy later).
   - UFW section (10) commented out with a one-line reason; `ufw` dropped from the apt prereqs list.
   - Fail2ban + unattended-upgrades untouched (unrelated to the conflict, still useful).
   - A clear "installing / skipping" manifest is visible near the top of the file (extends the existing numbered header comment style already in the original).
   - Final "Next steps" echo block updated to drop Caddy/UFW-specific instructions, mention existing cloudflared/Tailscale ingress instead.
   - `bash -n` passes; `shellcheck` (if available) has no new errors vs. the original file's baseline.
   - Original `scripts/vps-bootstrap.sh` untouched.
3. **Scope boundary:** no changes to OCI Security Lists/NSGs (out of band, console/CLI only), no doc changes (existing docs referencing `vps-bootstrap.sh` remain accurate — they describe the generic path, not this host), script is not executed as part of this task.
4. **Constraints:** kebab-case filename, keep under ~200 lines, same `set -euo pipefail` safety, no new external dependencies introduced.
5. **Touchpoints:** `scripts/` directory only.

## Steps

1. Write `scripts/vps-bootstrap-oci.sh` from the original, applying the comment-outs above.
2. Verify: `bash -n` syntax check + `shellcheck` if present.
3. `code-reviewer` subagent review (script-safety focus: root-run consequences, idempotency, no accidental re-introduction of the UFW/Caddy conflict).
4. Docs impact: none — existing docs describe the generic script, which is untouched; the new file is an opt-in variant not yet referenced anywhere.
5. Ask user about git commit.

## Todo

- [x] Plan written
- [x] Script implemented
- [x] Syntax verified (`bash -n`; shellcheck not installed on host)
- [x] Code review passed (code-reviewer subagent, no blocking findings)
- [ ] User asked about commit
