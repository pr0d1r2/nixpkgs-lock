#!/usr/bin/env bash
# Verify the README nixpkgs date badge against the pinned rev in flake.lock.
#
# The badge is STATIC text: shields.io can render a JSON value but cannot format
# one, and flake.lock stores the pin date only as an epoch (`lastModified`). So
# the date is written out by hand, and this script is what keeps it true -- any
# pin refresh that moves the lock without rewriting the badge fails here, in the
# same PR that moved it.
#
# Runnable by hand from the flake source root; the pin-badge check in flake.nix
# reads everything BELOW this preamble and runs it in the shell it supplies.
set -uo pipefail

# GNU date spells an epoch `-d @N`, BSD date `-r N`, and this script runs by
# hand on darwin as well as inside the check's coreutils shell.
epoch_date() {
  date -u -d "@$1" +"$2" 2>/dev/null || date -u -r "$1" +"$2"
}

epoch="$(jq -r '.nodes.nixpkgs.locked.lastModified' flake.lock)"

# Badge text is URL-encoded shields syntax: a literal dash is doubled.
want="$(epoch_date "$epoch" %Y-%m-%d)"
badge="$(epoch_date "$epoch" %Y--%m--%d)"

rc=0
grep -qF "nixpkgs%20date-$badge-" README.md || {
  echo "README nixpkgs date badge is stale:" >&2
  echo "  - flake.lock pins nixpkgs from $want" >&2
  echo "  - README.md must carry the badge text nixpkgs%20date-$badge-" >&2
  rc=1
}

# The exit status IS this test -- `exit $rc` would work standalone but, spliced
# into mkCheck, would skip its `touch $out` and fail the build on a clean pass.
[ "$rc" -eq 0 ]
