#!/usr/bin/env bash
# Refuse a pin that moves BACKWARDS in time.
#
# Usage: pin_monotonic.sh <previous-flake.lock> <candidate-flake.lock>
#
# This is deliberately ⊥ a flake check. mkCheck's src is the flake SOURCE --
# tracked files, no .git -- so a flake check is a pure function of ONE tree.
# Monotonicity is a property of TWO: this lock against the one before it. The
# callers supply both, and each gets the previous lock from a different place:
#
#   - nix/hooks/post-pin-update.sh   git show HEAD:flake.lock   (pre-commit)
#   - .github/workflows/guardrails   git show origin/<base>:... (pre-merge)
#
# The pre-merge caller is the load-bearing one. A stale pin PR was FORWARD when
# it was opened and only became backwards while it sat, so the hook -- which
# runs at bump time -- can never see it. Only the merge gate can. Measured:
# PR #10 sat seven weeks and would have moved the fleet pin from 2026-09-03
# back to 2026-06-30, 64 days, and every guardrail we had reported success.
#
# Compares lastModified, ⊥ rev: git revisions have no order. Equal PASSES --
# a no-op refresh is not a rollback. Only a DECREASE fails.
#
# PIN_ALLOW_ROLLBACK=1 permits a deliberate one, so a genuine upstream problem
# stays fixable without deleting the guard.
set -uo pipefail

if [ $# -ne 2 ]; then
  echo "usage: pin_monotonic.sh <previous-flake.lock> <candidate-flake.lock>" >&2
  exit 2
fi

previous="$1"
candidate="$2"

# GNU date spells an epoch `-d @N`, BSD date `-r N`.
epoch_date() {
  date -u -d "@$1" +%Y-%m-%d 2>/dev/null || date -u -r "$1" +%Y-%m-%d
}

pin_epoch() {
  jq -r '.nodes.nixpkgs.locked.lastModified // empty' "$1" 2>/dev/null
}

before="$(pin_epoch "$previous")"
after="$(pin_epoch "$candidate")"

# FAIL CLOSED on an unreadable pin. "Cannot tell" must ⊥ read as "fine": a lock
# this script cannot parse is a lock whose direction nobody has checked.
if ! printf '%s' "$before" | grep -qE '^[0-9]+$'; then
  echo "pin-monotonic: no readable nixpkgs lastModified in $previous" >&2
  exit 1
fi
if ! printf '%s' "$after" | grep -qE '^[0-9]+$'; then
  echo "pin-monotonic: no readable nixpkgs lastModified in $candidate" >&2
  exit 1
fi

if [ "$after" -ge "$before" ]; then
  exit 0
fi

echo "pin-monotonic: the pin moves BACKWARDS" >&2
echo "  - was $(epoch_date "$before") ($before)" >&2
echo "  - now $(epoch_date "$after") ($after)" >&2
echo "  - every repo in the fleet follows this pin; a rollback propagates silently" >&2
echo "  - set PIN_ALLOW_ROLLBACK=1 if the rollback is deliberate" >&2

[ "${PIN_ALLOW_ROLLBACK:-0}" = 1 ]
