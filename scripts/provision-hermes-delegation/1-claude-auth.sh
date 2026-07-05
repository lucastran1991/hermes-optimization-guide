#!/usr/bin/env bash
# ============================================================
# scripts/provision-hermes-delegation/1-claude-auth.sh
# ------------------------------------------------------------
# Gives the hermes user a Claude Code credential the fully
# scriptable way: writes ANTHROPIC_API_KEY=<key> into hermes's
# /home/hermes/.hermes/.env (scaffolded empty by
# vps-bootstrap-oci.sh section 7). Run after 0-gh-auth.sh.
#
# USAGE:
#   bash scripts/provision-hermes-delegation/1-claude-auth.sh --api-key=<key>
#
# MANUAL OAUTH ALTERNATIVE (NOT scripted, human-run only):
#   If a dedicated Claude subscription seat is preferred over an
#   API key, run interactively as hermes (needs a browser or SSH
#   loopback callback — cannot be automated in a curl|bash flow):
#     sudo -u hermes -i bash -c 'claude auth login'
#   or, for a headless long-lived token instead of a live browser
#   session:
#     sudo -u hermes -i bash -c 'claude setup-token'
#
#   Why this script defaults to the API-key path instead: a scoped,
#   independently-revocable API key has a SMALLER blast radius than
#   a full OAuth account seat. A same-UID delegated sub-session can
#   read hermes's .env either way, so the credential is exfiltratable
#   in both cases — but a leaked API key bounds the damage to that
#   key's spend/scope and rotates without touching the subscription
#   account, whereas a leaked OAuth seat yields account-level
#   impersonation until manually revoked. API-key-by-default is
#   therefore the safer choice here, not just the easier one.
#
# IDEMPOTENCY:
#   Re-running with a new --api-key replaces the existing
#   ANTHROPIC_API_KEY= line in place (appends only if the line is
#   absent) — never duplicates it. File permissions (600,
#   hermes:hermes) are re-asserted on every run.
#
# ARGV EXPOSURE (F15):
#   --api-key= sits in THIS SCRIPT's own argv (visible via `ps` /
#   /proc/<pid>/cmdline, and in shell history if typed inline) for
#   the run's duration — this is a live credential, not just an
#   installer input. Prefer env-indirection where possible (e.g.
#   `--api-key="$(cat keyfile)"` from a 600 file) and avoid running
#   this in a shell whose history is shared/persisted.
# ============================================================

set -euo pipefail

log()  { printf "\033[1;34m[claude-auth]\033[0m %s\n" "$*"; }
warn() { printf "\033[1;33m[warn]\033[0m %s\n" "$*"; }
die()  { printf "\033[1;31m[err]\033[0m %s\n" "$*" >&2; exit 1; }

API_KEY=""
for arg in "$@"; do
  case "$arg" in
    --api-key=*) API_KEY="${arg#--api-key=}" ;;
    *) die "Unknown argument: $arg" ;;
  esac
done

[ -n "$API_KEY" ] || die "Usage: $0 --api-key=<key>"

ENV_FILE="/home/hermes/.hermes/.env"
[ -f "$ENV_FILE" ] || die "$ENV_FILE not found — run bootstrap section 7 first (it scaffolds .env)"

# Validity gate (F14): cheap, deterministic parity check with the
# Phase 4/5 smoke-test gate — a bare non-empty grep would let a
# truncated/wrong-provider key through, only to fail later at the
# human end-to-end test.
[[ "$API_KEY" =~ ^sk-ant- ]] || die "key doesn't look like an Anthropic key (expected sk-ant- prefix)"

# ------------------------------------------------------------
# In-place update: replace an existing ANTHROPIC_API_KEY= line via
# a temp-file rewrite (not `sed -i` on a value that may contain
# slashes), append if the line is absent. Avoids duplicate lines.
# ------------------------------------------------------------
log "Writing ANTHROPIC_API_KEY into $ENV_FILE..."
TMP_FILE="$(mktemp)"
trap 'rm -f "$TMP_FILE"' EXIT

if grep -q '^ANTHROPIC_API_KEY=' "$ENV_FILE"; then
  found=0
  while IFS= read -r line || [ -n "$line" ]; do
    if [[ "$line" == ANTHROPIC_API_KEY=* ]]; then
      printf 'ANTHROPIC_API_KEY=%s\n' "$API_KEY" >> "$TMP_FILE"
      found=1
    else
      printf '%s\n' "$line" >> "$TMP_FILE"
    fi
  done < "$ENV_FILE"
  [ "$found" -eq 1 ] || die "internal error: ANTHROPIC_API_KEY= line disappeared mid-rewrite"
else
  cat "$ENV_FILE" > "$TMP_FILE"
  printf 'ANTHROPIC_API_KEY=%s\n' "$API_KEY" >> "$TMP_FILE"
fi

cat "$TMP_FILE" > "$ENV_FILE"

chmod 600 "$ENV_FILE"
chown hermes:hermes "$ENV_FILE"

# Verify the write landed without ever printing the key itself.
grep -q '^ANTHROPIC_API_KEY=.\+' "$ENV_FILE" || die "verification failed — ANTHROPIC_API_KEY= line is missing or empty after write"
log "ANTHROPIC_API_KEY set in $ENV_FILE (mode 600, hermes:hermes)."

# ------------------------------------------------------------
# Functional smoke (F14, non-fatal): surfaces a revoked/wrong-scope
# key here rather than at the deferred [HUMAN] end-to-end test.
# warn (not die): claude's key pickup may need more than .env alone,
# so a failure here is a signal, not a hard block.
# ------------------------------------------------------------
log "Running non-fatal functional smoke test as hermes..."
if sudo -u hermes -i bash -c 'export PATH="$HOME/.local/bin:$PATH"; claude -p "echo ok" --output-format json' >/dev/null 2>&1; then
  log "Functional smoke test passed."
else
  warn "Functional smoke test failed — key may be invalid/revoked, or claude needs more than .env alone. Verify manually: sudo -u hermes -i bash -c 'export PATH=\"\$HOME/.local/bin:\$PATH\"; claude -p \"echo ok\" --output-format json'"
fi
