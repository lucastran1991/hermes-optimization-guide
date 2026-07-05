#!/usr/bin/env bash
# ============================================================
# scripts/provision-hermes-delegation/0-gh-auth.sh
# ------------------------------------------------------------
# Authenticates the GitHub CLI (`gh`) for the hermes user
# non-interactively. Unblocks `ck init --install-skills` and any
# skill that shells out to `gh` (Phase 1's empty-skills gotcha —
# the bootstrap never installs or auths `gh`).
#
# USAGE (as root):
#   bash 0-gh-auth.sh --token=<PAT>
#   GH_TOKEN=<PAT> bash 0-gh-auth.sh
#
# REQUIRED PAT SCOPES: repo, read:org, gist
# Prefer a fine-grained, expiring, minimally-scoped token dedicated
# to the bot identity over the operator's long-lived classic PAT.
#
# IDEMPOTENCY: installs `gh` only if absent; re-running
# `gh auth login --with-token` safely overwrites/refreshes the
# existing host entry — safe to re-run with the same or a
# rotated token.
#
# SECURITY NOTE (argv exposure): the STDIN `--with-token` path
# keeps the PAT out of `gh`'s own argv, but the `--token=<PAT>`
# flag THIS script accepts is still visible in this script's own
# process argv (`ps aux` / `/proc/<pid>/cmdline`) for the
# invocation's runtime, and in shell history if typed inline.
# Prefer `GH_TOKEN=$(cat file) bash 0-gh-auth.sh` (env-indirection)
# over the inline flag, and never run this in a shell whose
# history is shared/persisted.
#
# Rollback: sudo -u hermes -i bash -c 'gh auth logout' — then
# revoke the PAT in GitHub settings.
# ============================================================

set -euo pipefail

log()  { printf "\033[1;34m[gh-auth]\033[0m %s\n" "$*"; }
warn() { printf "\033[1;33m[warn]\033[0m %s\n" "$*"; }
die()  { printf "\033[1;31m[err]\033[0m %s\n" "$*" >&2; exit 1; }

TOKEN=""
for arg in "$@"; do
  case "$arg" in
    --token=*) TOKEN="${arg#--token=}" ;;
    *) die "Unknown argument: $arg" ;;
  esac
done

TOKEN="${TOKEN:-${GH_TOKEN:-}}"
[ -n "$TOKEN" ] || die "supply --token=<PAT> or set GH_TOKEN (required scopes: repo, read:org, gist)"

# ------------------------------------------------------------
# Install gh idempotently, as root, BEFORE auth. Mirrors the
# NodeSource keyring+apt pattern (vps-bootstrap-oci.sh:68-74).
# ------------------------------------------------------------
if ! command -v gh >/dev/null 2>&1; then
  log "Installing GitHub CLI (gh)..."
  curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg | \
    gpg --dearmor -o /usr/share/keyrings/githubcli-archive-keyring.gpg
  chmod go+r /usr/share/keyrings/githubcli-archive-keyring.gpg
  echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" \
    > /etc/apt/sources.list.d/github-cli.list
  apt-get update -qq
  apt-get install -y -qq gh
else
  log "gh already installed, skipping install."
fi

# ------------------------------------------------------------
# Auth as hermes. Auth state is per-user under
# /home/hermes/.config/gh/ — must run AS hermes via the
# `bash -c '<cmd>'` wrapper form, NOT bare `sudo -u hermes -i gh …`
# (bare-binary form has confirmed PATH/quoting gotchas).
# STDIN delivery keeps the token out of gh's own argv.
# ------------------------------------------------------------
log "Authenticating gh for hermes..."
printf '%s' "$TOKEN" | sudo -u hermes -i bash -c 'gh auth login --hostname github.com --with-token' \
  || die "gh auth login failed for hermes"

# ------------------------------------------------------------
# Verify.
# ------------------------------------------------------------
if sudo -u hermes -i bash -c 'gh auth status' ; then
  log "gh auth verified for hermes."
else
  die "gh auth status failed for hermes after login"
fi
