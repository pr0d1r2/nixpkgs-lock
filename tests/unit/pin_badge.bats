#!/usr/bin/env bats
#
# Coverage for nix/check/pin_badge.sh -- the guardrail that keeps the README
# nixpkgs date badge in step with the pinned rev in flake.lock.
#
# The script reads ./flake.lock and ./README.md from the working directory, so
# every case builds a throwaway pair in $BATS_TEST_TMPDIR rather than touching
# the repo's own files.

# `run --separate-stderr` needs 1.5.0; declaring it also silences BW02.
bats_require_minimum_version 1.5.0

setup() {
  SCRIPT="$BATS_TEST_DIRNAME/../../nix/check/pin_badge.sh"
  WORK="$BATS_TEST_TMPDIR/work"
  mkdir -p "$WORK"
}

# 1788405554 is 2026-09-03T03:19:14Z -- deliberately in the small hours UTC, so
# a local-time conversion lands on the PREVIOUS day west of Greenwich.
EPOCH=1788405554

write_lock() {
  printf '{"nodes":{"nixpkgs":{"locked":{"lastModified":%s}}}}\n' "$1" >"$WORK/flake.lock"
}

write_readme() {
  printf '# repo\n\n%s\n\ntext\n' "$1" >"$WORK/README.md"
}

badge() {
  printf '[![nixpkgs date](https://img.shields.io/badge/nixpkgs%%20date-%s-blue)](x)' "$1"
}

check() {
  cd "$WORK" || return 1
  run "$SCRIPT"
}

@test "passes when the badge matches the pinned rev date" {
  write_lock "$EPOCH"
  write_readme "$(badge 2026--09--03)"
  check
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "fails when the badge names a different date" {
  write_lock "$EPOCH"
  write_readme "$(badge 2026--01--01)"
  check
  [ "$status" -eq 1 ]
}

@test "failure names both the pinned date and the expected badge text" {
  write_lock "$EPOCH"
  write_readme "$(badge 2026--01--01)"
  check
  [[ "$output" == *"pins nixpkgs from 2026-09-03"* ]]
  [[ "$output" == *"nixpkgs%20date-2026--09--03-"* ]]
}

@test "diagnostics go to stderr, leaving stdout clean" {
  write_lock "$EPOCH"
  write_readme "$(badge 2026--01--01)"
  cd "$WORK" || return 1
  run --separate-stderr "$SCRIPT"
  [ -z "$output" ]
  [ -n "$stderr" ]
}

@test "fails when the README carries no date badge at all" {
  write_lock "$EPOCH"
  write_readme "no badge here"
  check
  [ "$status" -eq 1 ]
}

@test "a single-dash date does not satisfy the doubled-dash badge text" {
  write_lock "$EPOCH"
  write_readme "$(badge 2026-09-03)"
  check
  [ "$status" -eq 1 ]
}

@test "the date is UTC, not the local timezone" {
  write_lock "$EPOCH"
  write_readme "$(badge 2026--09--03)"
  TZ=America/Los_Angeles check
  [ "$status" -eq 0 ]
}

@test "a moved pin fails a badge that was correct for the old rev" {
  write_lock 1786535285
  write_readme "$(badge 2026--08--12)"
  check
  [ "$status" -eq 0 ]

  write_lock "$EPOCH"
  check
  [ "$status" -eq 1 ]
}

@test "fails when flake.lock is missing" {
  write_readme "$(badge 2026--09--03)"
  check
  [ "$status" -eq 1 ]
}
