#!/usr/bin/env bash
# Verify the README nixpkgs date badge against the pinned rev in flake.lock.
#
# The badge is STATIC text: shields.io can render a JSON value but cannot format
# one, and flake.lock stores the pin date only as an epoch (`lastModified`). So
# the date is written out by hand, and this script is what keeps it true -- any
# pin refresh that moves the lock without rewriting the badge fails here, in the
# same PR that moved it.
#
# Run from the flake source root.

set -uo pipefail

epoch="$(jq -r '.nodes.nixpkgs.locked.lastModified' flake.lock)"

# Badge text is URL-encoded shields syntax: a literal dash is doubled.
want="$(date -u -d "@$epoch" +%Y-%m-%d)"
badge="$(date -u -d "@$epoch" +%Y--%m--%d)"

rc=0
grep -qF "nixpkgs%20date-$badge-" README.md || {
  echo "README nixpkgs date badge is stale:" >&2
  echo "  - flake.lock pins nixpkgs from $want" >&2
  echo "  - README.md must carry the badge text nixpkgs%20date-$badge-" >&2
  rc=1
}

exit "$rc"
