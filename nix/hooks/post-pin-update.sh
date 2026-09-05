#!/usr/bin/env bash
# Rewrite the README nixpkgs date badge from the pinned rev in flake.lock.
#
# This is the WRITER for the rule nix/check/pin_badge.sh enforces. A pin refresh
# moves flake.lock's `lastModified` and nothing else; without this, the badge
# goes stale and the check fails the very PR that moved the pin. Running it
# straight after `nix flake update` keeps the two in step deterministically,
# with no agent needed to read a CI failure and repair by hand.
#
# Idempotent: a badge already naming the pinned date is left untouched and the
# script still exits 0. Runnable by hand from the flake source root.
set -uo pipefail

# GNU date spells an epoch `-d @N`, BSD date `-r N`. Duplicated from
# nix/check/pin_badge.sh rather than sourced: the checker's body is spliced into
# a Nix derivation, so it cannot depend on a file being present beside it.
epoch_date() {
  date -u -d "@$1" +"$2" 2>/dev/null || date -u -r "$1" +"$2"
}

# REFUSE A ROLLBACK BEFORE WRITING ANYTHING. The badge writer is direction-
# blind by construction -- it renders whatever date the lock holds, so it will
# happily stamp an older one and leave every check agreeing with a pin that
# went backwards. Checked here, at bump time, so pin-refresh's fail-closed seam
# (V445) turns it into "no commit, no PR" rather than a red PR someone parks.
#
# The MERGE gate is the other half and lives in CI: a stale pin PR was forward
# when opened, so nothing running at bump time can catch it.
if git rev-parse --verify HEAD >/dev/null 2>&1; then
  _previous="$(mktemp)"
  if git show HEAD:flake.lock >"$_previous" 2>/dev/null; then
    if ! bash "$(dirname "$0")/../check/pin_monotonic.sh" "$_previous" flake.lock; then
      rm -f "$_previous"
      exit 1
    fi
  fi
  rm -f "$_previous"
fi

epoch="$(jq -r '.nodes.nixpkgs.locked.lastModified' flake.lock)"

# Badge text is URL-encoded shields syntax: a literal dash is doubled.
want="$(epoch_date "$epoch" %Y-%m-%d)"
badge="$(epoch_date "$epoch" %Y--%m--%d)"

if grep -qF "nixpkgs%20date-$badge-" README.md; then
  echo "post-pin-update: README badge already names $want"
  exit 0
fi

tmp="$(mktemp)"
sed -E "s|(nixpkgs%20date-)[0-9]{4}--[0-9]{2}--[0-9]{2}(-)|\1$badge\2|" README.md >"$tmp"

# A README that lost its badge must FAIL rather than be silently patched: the
# sed above rewrites a date, it cannot put a missing badge back, and a
# zero-substitution pass would otherwise report success having changed nothing.
if ! grep -qF "nixpkgs%20date-$badge-" "$tmp"; then
  rm -f "$tmp"
  echo "post-pin-update: no nixpkgs date badge found in README.md" >&2
  echo "  - expected badge text nixpkgs%20date-YYYY--MM--DD-" >&2
  exit 1
fi

mv "$tmp" README.md
echo "post-pin-update: README badge updated to $want"
