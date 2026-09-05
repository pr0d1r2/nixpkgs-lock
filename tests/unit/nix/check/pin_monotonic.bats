#!/usr/bin/env bats
#
# Coverage for nix/check/pin_monotonic.sh -- the guard that refuses a pin
# moving backwards in time. Both callers share this one implementation: the
# post-pin-update hook (bump time) and the guardrails CI job (merge time).

bats_require_minimum_version 1.5.0

setup() {
  SCRIPT="$BATS_TEST_DIRNAME/../../../../nix/check/pin_monotonic.sh"
  WORK="$BATS_TEST_TMPDIR/work"
  mkdir -p "$WORK"
}

# The real numbers from PR #10: main pinned 2026-09-03, the stale PR proposed
# 2026-06-30. 64 days backwards, and every guardrail reported success.
NEW=1788405554
OLD=1782847189

lock() {                                        # $1 = name, $2 = epoch
  printf '{"nodes":{"nixpkgs":{"locked":{"lastModified":%s}}}}\n' "$2" >"$WORK/$1"
  printf '%s' "$WORK/$1"
}

@test "a forward pin passes" {
  run bash "$SCRIPT" "$(lock old "$OLD")" "$(lock new "$NEW")"
  [ "$status" -eq 0 ]
}

@test "an unchanged pin passes -- a no-op refresh is not a rollback" {
  run bash "$SCRIPT" "$(lock old "$NEW")" "$(lock new "$NEW")"
  [ "$status" -eq 0 ]
}

@test "a backward pin FAILS -- the #10 case" {
  run bash "$SCRIPT" "$(lock old "$NEW")" "$(lock new "$OLD")"
  [ "$status" -eq 1 ]
}

@test "one second backwards is still backwards" {
  run bash "$SCRIPT" "$(lock old "$NEW")" "$(lock new "$((NEW - 1))")"
  [ "$status" -eq 1 ]
}

@test "the failure names both dates and the fleet consequence" {
  run bash "$SCRIPT" "$(lock old "$NEW")" "$(lock new "$OLD")"
  [[ "$output" == *"was 2026-09-03"* ]]
  [[ "$output" == *"now 2026-06-30"* ]]
  [[ "$output" == *"propagates silently"* ]]
}

@test "PIN_ALLOW_ROLLBACK=1 permits a deliberate rollback" {
  PIN_ALLOW_ROLLBACK=1 run bash "$SCRIPT" "$(lock old "$NEW")" "$(lock new "$OLD")"
  [ "$status" -eq 0 ]
}

@test "PIN_ALLOW_ROLLBACK=1 still reports what it allowed" {
  PIN_ALLOW_ROLLBACK=1 run bash "$SCRIPT" "$(lock old "$NEW")" "$(lock new "$OLD")"
  [[ "$output" == *"moves BACKWARDS"* ]]
}

@test "an unreadable previous lock FAILS -- cannot tell is not fine" {
  printf 'not json\n' >"$WORK/broken"
  run bash "$SCRIPT" "$WORK/broken" "$(lock new "$NEW")"
  [ "$status" -eq 1 ]
}

@test "an unreadable candidate lock FAILS" {
  printf '{"nodes":{}}\n' >"$WORK/empty"
  run bash "$SCRIPT" "$(lock old "$OLD")" "$WORK/empty"
  [ "$status" -eq 1 ]
}

@test "a rollback is NOT waved through by the allow flag being unset to junk" {
  PIN_ALLOW_ROLLBACK=yes run bash "$SCRIPT" "$(lock old "$NEW")" "$(lock new "$OLD")"
  [ "$status" -eq 1 ]
}

@test "wrong argument count exits 2, distinct from a rollback" {
  run bash "$SCRIPT" "$(lock old "$OLD")"
  [ "$status" -eq 2 ]
}

@test "the script is runnable by hand -- executable, with a bash shebang" {
  [ -x "$SCRIPT" ]
  [ "$(head -n 1 "$SCRIPT")" = "#!/usr/bin/env bash" ]
}
