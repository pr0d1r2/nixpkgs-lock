#!/usr/bin/env bats

bats_require_minimum_version 1.5.0

setup() {
  CONFIG="$BATS_TEST_DIRNAME/../../.hallucinogen.yml"
}

@test "pin-refresh runs the post-pin-update hook after the lock update" {
  run awk '
    /^pin-refresh:/ { in_refresh = 1; next }
    in_refresh && /^  after-update:/ { in_after = 1; next }
    in_after && /^    - / { print; next }
    in_after && !/^    - / { exit }
  ' "$CONFIG"
  [ "$status" -eq 0 ]
  [ "$output" = "    - nix/hooks/post-pin-update.sh" ]
}

@test "pin-refresh enables the fleet-wide monotonicity guard" {
  run awk '
    /^pin-refresh:/ { in_refresh = 1; next }
    in_refresh && /^  monotonicity: / { print $2; exit }
    in_refresh && !/^  / { exit 1 }
  ' "$CONFIG"
  [ "$status" -eq 0 ]
  [ "$output" = "true" ]
}

@test "the configured hook is executable" {
  [ -x "$BATS_TEST_DIRNAME/../../nix/hooks/post-pin-update.sh" ]
}
