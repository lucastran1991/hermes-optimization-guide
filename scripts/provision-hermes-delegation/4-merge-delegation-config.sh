#!/usr/bin/env bash
# ============================================================
# scripts/provision-hermes-delegation/4-merge-delegation-config.sh
# ------------------------------------------------------------
# Wires the `delegation:` block from this repo's
# templates/config/production.yaml into the LIVE
# /home/hermes/.hermes/config.yaml (the file hermes.service
# actually reads at runtime — distinct from the repo template),
# substituting `ccs_profile:` with the profile name provisioned
# by 2-ccs-profile.sh (or a bridge-instance name, if that path
# was used instead). Run this LAST, after a ccs_profile already
# exists on the host.
#
# USAGE:
#   sudo bash 4-merge-delegation-config.sh --ccs-profile=<name> [--force]
#
# --ccs-profile=<name>  Required. Must match a profile name that
#                        already exists on this host.
# --force                Bypass the stale-canonical-clone guard.
#
# GUIDE_DIR defaults to /opt/hermes-optimization-guide (same
# bootstrap-canonical clone convention as deploy-systemd-units.sh)
# — the `delegation:` block is always read from there, never from
# wherever this script file happens to live.
#
# IDEMPOTENCY: re-running REPLACES the existing `delegation:`
# block (bounded-block delete, then insert) — it never produces a
# second `delegation:` top-level key. A duplicate top-level key is
# valid YAML (yaml.safe_load silently keeps the last occurrence),
# so YAML-validity alone cannot be trusted to catch a duplicate —
# this script asserts `grep -c '^delegation:'` == 1 after merging.
#
# Does NOT restart hermes.service. Config re-read AND the
# in-process skill-command registry are both stale until a manual
# restart — fold that into your real /coding-agent-delegate test
# rather than double-bouncing the service here.
# ============================================================

set -euo pipefail

log()  { printf "\033[1;34m[merge-delegation-config]\033[0m %s\n" "$*"; }
warn() { printf "\033[1;33m[warn]\033[0m %s\n" "$*"; }
die()  { printf "\033[1;31m[err]\033[0m %s\n" "$*" >&2; exit 1; }

FORCE=0
PROFILE=""

for arg in "$@"; do
  case "$arg" in
    --ccs-profile=*) PROFILE="${arg#*=}" ;;
    --force) FORCE=1 ;;
    *) die "Unknown argument: $arg (expected --ccs-profile=<name> [--force])" ;;
  esac
done

[ -n "$PROFILE" ] || die "Missing required --ccs-profile=<name>"
[[ "$PROFILE" =~ ^[a-zA-Z0-9_-]+$ ]] || die "invalid --ccs-profile name: $PROFILE (allowed: letters, digits, _, -)"

GUIDE_DIR="${GUIDE_DIR:-/opt/hermes-optimization-guide}"
SRC_YAML="$GUIDE_DIR/templates/config/production.yaml"
CONFIG="/home/hermes/.hermes/config.yaml"

[ -f "$SRC_YAML" ] || die "Source template not found: $SRC_YAML (is GUIDE_DIR correct? run from a checkout or set GUIDE_DIR)"
[ -f "$CONFIG" ] || die "Live config not found: $CONFIG (has hermes been bootstrapped yet?)"

# ------------------------------------------------------------
# Stale-canonical guard: refuse to merge from a clone that is
# behind origin/main, or a pre-fix delegation: block could get
# grafted into the live config. Mirrors deploy-systemd-units.sh.
# ------------------------------------------------------------
if git -C "$GUIDE_DIR" fetch --quiet origin 2>/dev/null; then
  if ! behind="$(git -C "$GUIDE_DIR" rev-list --count main..origin/main 2>/dev/null)"; then
    warn "Could not compute how far $GUIDE_DIR is behind origin/main (branch state unclear) — proceeding with the clone's current HEAD."
    behind=0
  fi
  if [ "$behind" -gt 0 ] && [ "$FORCE" -ne 1 ]; then
    die "Canonical clone $GUIDE_DIR is $behind commit(s) behind origin/main — reconcile with 'git -C $GUIDE_DIR pull --ff-only' before merging, or pass --force."
  fi
else
  warn "Could not fetch $GUIDE_DIR against origin (offline or no perms) — proceeding with the clone's current HEAD."
fi

# ------------------------------------------------------------
# Ensure PyYAML is available for the validation gate below. Not
# part of the bootstrap apt list, so guard-install it (idempotent).
# ------------------------------------------------------------
if ! python3 -c 'import yaml' 2>/dev/null; then
  log "PyYAML not found — installing python3-yaml..."
  apt-get install -y -qq python3-yaml || die "failed to install python3-yaml (required for YAML validation)"
fi

# ------------------------------------------------------------
# Extract the bounded delegation: block (exclusive of the next
# top-level key, e.g. acp:) and substitute ccs_profile: within it.
# ------------------------------------------------------------
BLOCK_FILE="$(mktemp)"
trap 'rm -f "$BLOCK_FILE" "${CONFIG_TMP:-}"' EXIT

awk '/^delegation:/{f=1} f && /^[a-zA-Z_][a-zA-Z0-9_]*:/ && !/^delegation:/{exit} f{print}' "$SRC_YAML" \
  | sed 's/^\( *ccs_profile:\).*/\1 '"$PROFILE"'/' \
  > "$BLOCK_FILE"

[ -s "$BLOCK_FILE" ] || die "Extracted delegation: block is empty — check $SRC_YAML for a top-level 'delegation:' key"

# ------------------------------------------------------------
# Backup before editing.
# ------------------------------------------------------------
cp "$CONFIG" "$CONFIG.bak"
log "Backed up $CONFIG -> $CONFIG.bak"

# ------------------------------------------------------------
# Replace-not-append (never duplicate a top-level delegation:
# key): if one already exists, strip the existing bounded block
# first using the same terminator, inverted.
# ------------------------------------------------------------
CONFIG_TMP="$(mktemp)"
if grep -q '^delegation:' "$CONFIG"; then
  log "Existing delegation: block found — replacing it."
  awk '
    /^delegation:/{indel=1}
    indel && /^[a-zA-Z_][a-zA-Z0-9_]*:/ && !/^delegation:/{indel=0}
    !indel{print}
  ' "$CONFIG" > "$CONFIG_TMP"
else
  log "No existing delegation: block — inserting."
  cp "$CONFIG" "$CONFIG_TMP"
fi

# Ensure a trailing newline before appending the new block so it
# doesn't get glued onto the previous line.
[ -s "$CONFIG_TMP" ] && [ "$(tail -c1 "$CONFIG_TMP" | wc -l)" -eq 0 ] && printf '\n' >> "$CONFIG_TMP"
cat "$BLOCK_FILE" >> "$CONFIG_TMP"
mv "$CONFIG_TMP" "$CONFIG"
CONFIG_TMP=""

# ------------------------------------------------------------
# Duplicate-key assert (YAML-validity alone can't catch this —
# yaml.safe_load silently keeps the last of two identical top-
# level keys). Restore backup + die if the merge produced two.
# ------------------------------------------------------------
count="$(grep -c '^delegation:' "$CONFIG")"
if [ "$count" -ne 1 ]; then
  cp "$CONFIG.bak" "$CONFIG"
  die "post-merge assert failed: expected exactly 1 top-level 'delegation:' key, found $count — restored $CONFIG.bak"
fi

# ------------------------------------------------------------
# YAML-validate the merged config; restore backup + die on
# failure.
# ------------------------------------------------------------
if ! python3 -c 'import yaml, sys; yaml.safe_load(open(sys.argv[1]))' "$CONFIG"; then
  cp "$CONFIG.bak" "$CONFIG"
  die "merged config failed YAML validation — restored $CONFIG.bak"
fi

log "Merged delegation: block (ccs_profile: $PROFILE) into $CONFIG"
log "hermes.service was NOT restarted — the config re-read and the in-process"
log "skill-command registry are both stale until a manual restart. Restart it"
log "and fold the check into your real /coding-agent-delegate test:"
log "  sudo systemctl restart hermes.service"
