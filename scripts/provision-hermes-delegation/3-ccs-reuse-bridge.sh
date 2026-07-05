#!/usr/bin/env bash
# ============================================================
# scripts/provision-hermes-delegation/3-ccs-reuse-bridge.sh
# ------------------------------------------------------------
# !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
# !!                                                         !!
# !!   INTERNAL-FORK-ONLY  --  DO NOT UPSTREAM THIS SCRIPT   !!
# !!                                                         !!
# !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
#
# This script REUSES a real person's CCS identity (e.g. "ken")
# by copying their credential files into hermes's home so the
# bot can call `ccs <name> ...` under that identity. This means:
#
#   - SHARED QUOTA:  hermes's delegated tasks bill/consume the
#                    personal account's usage.
#   - IMPERSONATION: delegated sub-sessions act AS that person,
#                    not as a distinct bot identity.
#   - A same-UID sub-session on the hermes host can read the
#                    copied credential pair.
#
# This exists ONLY because this repo is a personal fork
# (lucastran1991/hermes-optimization-guide). It will NEVER be
# upstreamed to the public OnlyTerp/hermes-optimization-guide.
#
# PREFER `2-ccs-profile.sh` INSTEAD: it provisions a dedicated
# bot CCS profile with its own identity and quota. Only reach
# for this reuse-bridge script as a temporary stopgap when no
# dedicated bot account exists yet.
#
# This script refuses to do anything unless you pass BOTH
# --instance=<name> AND --i-understand-the-risk.
#
# USAGE:
#   bash 3-ccs-reuse-bridge.sh --instance=<name> --i-understand-the-risk
#
# Non-interactive, idempotent (re-copy overwrites). Must be run
# as (or via sudo as) a user that can read /home/ubuntu/.ccs and
# write /home/hermes/.ccs, then chown to hermes:hermes.
# ============================================================

set -euo pipefail

log()  { printf "\033[1;34m[ccs-reuse-bridge]\033[0m %s\n" "$*"; }
warn() { printf "\033[1;33m[warn]\033[0m %s\n" "$*"; }
die()  { printf "\033[1;31m[err]\033[0m %s\n" "$*" >&2; exit 1; }

RISK_WARNING="Refusing to reuse a personal CCS identity: this shares quota and \
impersonates a real person's account for hermes's delegated tasks. Re-run with \
--i-understand-the-risk only if you have deliberately chosen the reuse-bridge \
stopgap over the dedicated bot profile in 2-ccs-profile.sh."

INSTANCE=""
UNDERSTOOD=0

for arg in "$@"; do
  case "$arg" in
    --instance=*) INSTANCE="${arg#--instance=}" ;;
    --i-understand-the-risk) UNDERSTOOD=1 ;;
    *) die "Unknown argument: $arg" ;;
  esac
done

# ------------------------------------------------------------
# Risk gate FIRST (F-gate): refuse before touching any path or
# copying anything unless the operator explicitly acknowledged
# the shared-quota / impersonation risk.
# ------------------------------------------------------------
if [ "$UNDERSTOOD" -ne 1 ]; then
  warn "$RISK_WARNING"
  die "refusing to reuse a personal CCS identity without --i-understand-the-risk"
fi

[ -n "$INSTANCE" ] || die "missing required --instance=<name>"

# ------------------------------------------------------------
# Name validation (F3) BEFORE building any path. This script
# runs with root/hermes-owning privileges; an unsanitized name
# like "../../etc" would turn it into a path-traversal primitive.
# ------------------------------------------------------------
[[ "$INSTANCE" =~ ^[a-zA-Z0-9_-]+$ ]] || die "invalid instance name: $INSTANCE"

SRC_HOME="${SRC_HOME:-/home/ubuntu/.ccs}"
DST_HOME="${DST_HOME:-/home/hermes/.ccs}"
SRC="$SRC_HOME/instances/$INSTANCE"
DST="$DST_HOME/instances/$INSTANCE"

# Source-exists gate.
[ -d "$SRC" ] || die "no such instance: $SRC"

# ------------------------------------------------------------
# Scoped copy (F2, NOT `cp -a`): copy ONLY the two files CCS
# needs to route the profile. Explicitly excluded: history.jsonl
# (real conversation transcripts/PII), .claude.json's sibling
# projects/, session-env/, plans-registries/, file-history/ --
# a blanket recursive copy would export a real person's chat
# history into a service account's home.
# ------------------------------------------------------------
[ -f "$SRC/.credentials.json" ] || die "no credential file in source instance: $SRC/.credentials.json"

mkdir -p "$DST"
cp "$SRC/.credentials.json" "$DST/.credentials.json"
chmod 600 "$DST/.credentials.json"
log "copied .credentials.json"

if [ -f "$SRC/.claude.json" ]; then
  cp "$SRC/.claude.json" "$DST/.claude.json"
  chmod 600 "$DST/.claude.json"
  log "copied .claude.json"
else
  warn "no .claude.json in source instance (continuing with credentials only)"
fi

# ------------------------------------------------------------
# Profile registration (F9): hermes's own ~/.ccs/config.yaml
# resolves profiles via a top-level `accounts:` block (NOT the
# instances/ directory name). Merge the instance's `accounts.
# <name>:` entry (created, last_used, context_mode) from the
# source root config if it's not already registered in the
# destination root config.
# ------------------------------------------------------------
SRC_CONFIG="$SRC_HOME/config.yaml"
DST_CONFIG="$DST_HOME/config.yaml"
config_merged=0

if [ -f "$DST_CONFIG" ] && grep -qE "^  ${INSTANCE}:\$" "$DST_CONFIG"; then
  log "profile '$INSTANCE' already registered in $DST_CONFIG, skipping merge"
elif [ -f "$SRC_CONFIG" ]; then
  # Extract the "  <name>:" line and its indented (4-space) child
  # keys from the source config.
  account_block="$(awk -v name="$INSTANCE" '
    $0 ~ "^  " name ":$" { found=1; print; next }
    found && /^    / { print; next }
    { found=0 }
  ' "$SRC_CONFIG")"

  if [ -z "$account_block" ]; then
    warn "no accounts.$INSTANCE entry found in $SRC_CONFIG, skipping profile registration"
  elif [ ! -f "$DST_CONFIG" ]; then
    die "destination config missing: $DST_CONFIG (cannot register profile)"
  elif ! grep -qE "^accounts:\$" "$DST_CONFIG"; then
    die "destination config has no top-level 'accounts:' block: $DST_CONFIG"
  else
    tmp_config="$(mktemp)"
    awk -v block="$account_block" '
      { print }
      /^accounts:$/ && !inserted { print block; inserted=1 }
    ' "$DST_CONFIG" > "$tmp_config"
    mv "$tmp_config" "$DST_CONFIG"
    config_merged=1
    log "registered profile '$INSTANCE' in $DST_CONFIG"
  fi
else
  warn "source config not found: $SRC_CONFIG, skipping profile registration"
fi

# ------------------------------------------------------------
# Re-own the copied files (and config.yaml if it was touched)
# to hermes so the bot's own ccs invocations can read them.
# ------------------------------------------------------------
chown -R hermes:hermes "$DST"
if [ "$config_merged" -eq 1 ]; then
  chown hermes:hermes "$DST_CONFIG"
fi

# ------------------------------------------------------------
# Smoke test: confirm the reused profile actually resolves and
# can complete a trivial call before declaring success.
# ------------------------------------------------------------
log "running smoke test as hermes..."
if ! sudo -u hermes -i bash -c 'ccs "'"$INSTANCE"'" -p "echo ok" --output-format json'; then
  die "smoke test failed: ccs $INSTANCE did not respond successfully"
fi

log "done: instance '$INSTANCE' bridged to hermes and smoke test passed"
