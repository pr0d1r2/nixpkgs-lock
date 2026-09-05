#!/usr/bin/env bats
#
# Coverage for nix/hooks/post-pin-update.sh -- the writer that keeps the README
# nixpkgs date badge in step with flake.lock, so a pin refresh does not leave
# nix/check/pin_badge.sh failing the PR that moved the pin.
#
# Each case builds a throwaway flake.lock and README.md in $BATS_TEST_TMPDIR;
# the repo's own files are never touched.

bats_require_minimum_version 1.5.0

setup() {
  SCRIPT="$BATS_TEST_DIRNAME/../../../../nix/hooks/post-pin-update.sh"
  CHECK="$BATS_TEST_DIRNAME/../../../../nix/check/pin_badge.sh"
  WORK="$BATS_TEST_TMPDIR/work"
  mkdir -p "$WORK"
}

# 1788405554 is 2026-09-03T03:19:14Z; 1786535285 is 2026-08-12. Both in the
# small hours UTC, so a local-time conversion lands on the previous day.
NEW=1788405554
OLD=1786535285

write_lock() {
  printf '{"nodes":{"nixpkgs":{"locked":{"lastModified":%s}}}}\n' "$1" >"$WORK/flake.lock"
}

badge() {
  printf '[![nixpkgs date](https://img.shields.io/badge/nixpkgs%%20date-%s-blue)](x)' "$1"
}

write_readme() {
  printf '# repo\n\n%s\n\ntrailing text\n' "$1" >"$WORK/README.md"
}

run_writer() {
  cd "$WORK" || return 1
  run bash "$SCRIPT"
}

@test "a stale badge is rewritten to the pinned date" {
  write_lock "$NEW"
  write_readme "$(badge 2026--01--01)"
  run_writer
  [ "$status" -eq 0 ]
  grep -qF "nixpkgs%20date-2026--09--03-" "$WORK/README.md"
}

@test "a badge already naming the pinned date is left untouched" {
  write_lock "$NEW"
  write_readme "$(badge 2026--09--03)"
  before="$(cat "$WORK/README.md")"
  run_writer
  [ "$status" -eq 0 ]
  [ "$before" = "$(cat "$WORK/README.md")" ]
}

@test "running twice changes nothing the second time" {
  write_lock "$NEW"
  write_readme "$(badge 2026--01--01)"
  run_writer
  once="$(cat "$WORK/README.md")"
  run_writer
  [ "$status" -eq 0 ]
  [ "$once" = "$(cat "$WORK/README.md")" ]
}

@test "the rest of the README survives the rewrite" {
  write_lock "$NEW"
  write_readme "$(badge 2026--01--01)"
  run_writer
  grep -qF "# repo" "$WORK/README.md"
  grep -qF "trailing text" "$WORK/README.md"
}

@test "a README with no date badge fails rather than being patched" {
  write_lock "$NEW"
  write_readme "no badge here"
  before="$(cat "$WORK/README.md")"
  run_writer
  [ "$status" -eq 1 ]
  [ "$before" = "$(cat "$WORK/README.md")" ]
}

@test "the date is UTC, not the local timezone" {
  write_lock "$NEW"
  write_readme "$(badge 2026--01--01)"
  TZ=America/Los_Angeles run_writer
  [ "$status" -eq 0 ]
  grep -qF "nixpkgs%20date-2026--09--03-" "$WORK/README.md"
}

@test "writing then checking agrees -- the check passes on the writer's output" {
  write_lock "$NEW"
  write_readme "$(badge 2026--01--01)"
  run_writer
  [ "$status" -eq 0 ]
  cd "$WORK" || return 1
  run bash "$CHECK"
  [ "$status" -eq 0 ]
}

@test "a pin moving backwards is rewritten too" {
  write_lock "$OLD"
  write_readme "$(badge 2026--09--03)"
  run_writer
  [ "$status" -eq 0 ]
  grep -qF "nixpkgs%20date-2026--08--12-" "$WORK/README.md"
}

@test "the script is runnable by hand -- executable, with a bash shebang" {
  [ -x "$SCRIPT" ]
  [ "$(head -n 1 "$SCRIPT")" = "#!/usr/bin/env bash" ]
}
