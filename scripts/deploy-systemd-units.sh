#!/usr/bin/env bash
# ============================================================
# scripts/deploy-systemd-units.sh
# ------------------------------------------------------------
# Syncs templates/systemd/*.service from the canonical on-host
# clone to /etc/systemd/system/, reloading and restarting only
# what actually changed. Run this after editing any unit
# template so the fix doesn't sit undeployed (see the P0
# seccomp incident this script exists to prevent recurrence of).
#
# USAGE:
#   bash scripts/deploy-systemd-units.sh [--force]
#
# GUIDE_DIR defaults to /opt/hermes-optimization-guide, the
# bootstrap-canonical clone (see vps-bootstrap-oci.sh GUIDE_DIR).
# Templates are always read from there, never from this script's
# own location, so the source of truth is unambiguous regardless
# of where the script file happens to be invoked from.
#
# Non-destructive, idempotent, re-runnable. Self-elevating via
# sudo per privileged command.
# ============================================================

set -euo pipefail

log()  { printf "\033[1;34m[deploy]\033[0m %s\n" "$*"; }
warn() { printf "\033[1;33m[warn]\033[0m %s\n" "$*"; }
die()  { printf "\033[1;31m[err]\033[0m %s\n" "$*" >&2; exit 1; }

FORCE=0
for arg in "$@"; do
  case "$arg" in
    --force) FORCE=1 ;;
    *) die "Unknown argument: $arg" ;;
  esac
done

GUIDE_DIR="${GUIDE_DIR:-/opt/hermes-optimization-guide}"
TPL_DIR="$GUIDE_DIR/templates/systemd"

[ -d "$TPL_DIR" ] || die "Template dir not found: $TPL_DIR (is GUIDE_DIR correct?)"

# ------------------------------------------------------------
# Stale-canonical guard: refuse to deploy from a clone that is
# behind origin/main, or a pre-fix template could get reinstalled.
# ------------------------------------------------------------
if git -C "$GUIDE_DIR" fetch --quiet origin 2>/dev/null; then
  if ! behind="$(git -C "$GUIDE_DIR" rev-list --count main..origin/main 2>/dev/null)"; then
    warn "Could not compute how far $GUIDE_DIR is behind origin/main (branch state unclear) — proceeding with the clone's current HEAD."
    behind=0
  fi
  if [ "$behind" -gt 0 ] && [ "$FORCE" -ne 1 ]; then
    die "Canonical clone $GUIDE_DIR is $behind commit(s) behind origin/main — reconcile with 'git -C $GUIDE_DIR pull --ff-only' before deploying, or pass --force."
  fi
else
  warn "Could not fetch $GUIDE_DIR against origin (offline or no perms) — proceeding with the clone's current HEAD."
fi

shopt -s nullglob
changed=()
unchanged=()
restarted=()
deployed_inactive=()

for tpl in "$TPL_DIR"/*.service; do
  name="$(basename "$tpl")"
  live="/etc/systemd/system/$name"

  if [ ! -f "$live" ] || ! diff -q "$tpl" "$live" >/dev/null 2>&1; then
    log "Installing changed unit: $name"
    sudo install -m 0644 -o root -g root "$tpl" "$live"
    changed+=("$name")
  else
    unchanged+=("$name")
  fi
done

if ((${#changed[@]})); then
  log "Reloading systemd (units changed)..."
  sudo systemctl daemon-reload

  for name in "${changed[@]}"; do
    if systemctl is-active --quiet "$name"; then
      log "Restarting active unit: $name"
      sudo systemctl restart "$name"
      restarted+=("$name")
    else
      deployed_inactive+=("$name")
    fi
  done
fi

log "Summary:"
if ((${#changed[@]})); then
  printf "  changed:            %s\n" "${changed[*]}"
else
  printf "  changed:            none\n"
fi
if ((${#restarted[@]})); then
  printf "  restarted:          %s\n" "${restarted[*]}"
fi
if ((${#deployed_inactive[@]})); then
  printf "  deployed (inactive): %s\n" "${deployed_inactive[*]}"
fi
if ((${#unchanged[@]})); then
  printf "  unchanged (skipped): %s\n" "${unchanged[*]}"
else
  printf "  unchanged (skipped): none\n"
fi

if ((${#changed[@]} == 0)); then
  log "0 changed, nothing to do."
fi
