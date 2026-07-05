#!/usr/bin/env bash
# ============================================================
# scripts/provision-hermes-delegation/2-ccs-profile.sh
# ------------------------------------------------------------
# Provisions the hermes-dedicated CCS API profile (ccs-hermes)
# that templates/config/production.yaml's
# `delegation.ccs_profile: ccs-hermes` already points at. This
# is the DEDICATED-credential path — a real, separate key,
# quota, and audit trail for the bot — as opposed to the
# internal-fork-only credential-reuse bridge in
# 3-ccs-bridge.sh. Pick ONE of the two per host.
#
# USAGE:
#   sudo bash 2-ccs-profile.sh --preset=<preset-id> --api-key=<key>
#
# Both flags are required. <preset-id> is whatever `ccs api
# create --help` lists (anthropic, glm, km, openrouter,
# deepseek, qwen, ...) matching the provider the dedicated key
# belongs to.
#
# ARGV LEAK WARNING (accepted trade-off, decision F15):
#   The non-interactive `--api-key --yes` form is the only
#   scriptable one (the safer interactive wizard is
#   browser/prompt-bound and can't run under `curl | sudo
#   bash`). That means the key sits in this process's argv —
#   visible via `ps` and shell history — for the run's
#   duration. Prefer passing the key via a short-lived env var
#   substituted into the invocation over pasting it directly on
#   an interactive shell if history leak is a concern. Rotate
#   the key at the provider if this exposure is unacceptable.
#
# IDEMPOTENCY (F8 — verified path, NOT `--force`):
#   `ccs api create --help` does not document a `--force`
#   overwrite flag in this repo's verified plan history, so
#   idempotency here is: `ccs api remove ccs-hermes` (ignored
#   if the profile doesn't exist yet) THEN `ccs api create
#   ccs-hermes ...`. Re-running this script is always safe.
#
# NAME HARDCODED (no --name flag):
#   The profile name `ccs-hermes` is a constant, not a flag —
#   it matches production.yaml's existing
#   `delegation.ccs_profile: ccs-hermes` value, so no config
#   edit is ever required (DRY).
#
# Runs `ccs` AS the hermes user via `sudo -u hermes -i bash -c
# '...'` (F12 wrapper form) so profile state lands under
# /home/hermes/.ccs/, never under the operator's own
# /home/ubuntu/.ccs/. The key is never echoed.
#
# MANDATORY SMOKE-TEST GATE:
#   harness: ccs is unusable until `ccs ccs-hermes -p "echo ok"
#   --output-format json` exits 0. There is NO auto-fallback to
#   harness: bare — a silent partial success would leave
#   delegation broken in a way that's hard to diagnose later.
# ============================================================

set -euo pipefail

log()  { printf "\033[1;34m[ccs-profile]\033[0m %s\n" "$*"; }
warn() { printf "\033[1;33m[warn]\033[0m %s\n" "$*"; }
die()  { printf "\033[1;31m[err]\033[0m %s\n" "$*" >&2; exit 1; }

PROFILE_NAME="ccs-hermes"
PRESET=""
API_KEY=""

for arg in "$@"; do
  case "$arg" in
    --preset=*) PRESET="${arg#*=}" ;;
    --api-key=*) API_KEY="${arg#*=}" ;;
    *) die "Unknown argument: $arg (expected --preset=<id> --api-key=<key>)" ;;
  esac
done

[ -n "$PRESET" ] || die "Missing required --preset=<id> (e.g. anthropic, glm, km, openrouter, deepseek, qwen)"
[ -n "$API_KEY" ] || die "Missing required --api-key=<key>"

# ------------------------------------------------------------
# Idempotent reset (F8): remove any existing profile of the
# same name first, ignoring failure if it's not present yet.
# This is the verified idempotency path — NOT the unverified
# `--force` flag.
# ------------------------------------------------------------
log "Resetting any existing '$PROFILE_NAME' profile (idempotent)..."
sudo -u hermes -i bash -c "ccs api remove $PROFILE_NAME" 2>/dev/null || true

# ------------------------------------------------------------
# Create the dedicated profile as hermes (F12 wrapper form).
# $PRESET/$API_KEY are passed via env-var indirection (`env
# VAR=val bash -c '... "$VAR" ...'`), NOT string-concatenated
# into the bash -c source — concatenation would let a value
# containing a quote or `$(...)` break out of its quoting and
# execute arbitrary code as hermes when the inner shell
# re-parses the string. The key is never printed by this script.
# ------------------------------------------------------------
log "Creating '$PROFILE_NAME' profile (preset: $PRESET)..."
sudo -u hermes -i env CCS_PRESET="$PRESET" CCS_API_KEY="$API_KEY" \
  bash -c 'ccs api create '"$PROFILE_NAME"' --preset "$CCS_PRESET" --api-key "$CCS_API_KEY" --target claude --yes' \
  || die "ccs api create failed for '$PROFILE_NAME' — check preset id and hermes user's ccs installation"

# ------------------------------------------------------------
# Mandatory smoke-test gate. No fallback: if this fails,
# harness: ccs stays unusable and the script must fail loudly
# rather than report a false success.
# ------------------------------------------------------------
log "Running smoke test against '$PROFILE_NAME'..."
if ! sudo -u hermes -i bash -c "ccs $PROFILE_NAME -p \"echo ok\" --output-format json"; then
  die "smoke-test failed — harness: ccs not usable; check credential/preset"
fi

log "Done. '$PROFILE_NAME' profile created and smoke-tested successfully."
