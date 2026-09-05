# SPEC -- nixpkgs-lock

## S.G Goal

Centralized nixpkgs version pin for all pr0d1r2/nix-* repos. Single
flake.lock is source of truth. The hallucinogen tend loop's `pin-refresh`
agent action bumps the pin, opens a PR, drives it green, and merges it.
nixpkgs-lock is bumped first as the pin standard; downstream repos
refresh to its validated rev. No manual intervention on happy path.

## S.C Constraints

- C1: Minimal flake -- inputs only, no outputs, no code
- C2: Pin nixpkgs stable channel (nixos-26.05)
- C3: Main branch protected -- all changes via PR
- C4: Pin updates via hallucinogen tend loop `pin-refresh` -- `nix flake update`, PR if lock changed
- C5: Downstream repos refreshed by the tend loop -- no per-repo cron workflows
- C6: No-op safe -- if nixpkgs-lock rev unchanged, `nix flake update nixpkgs-lock` produces no diff, no PR created
- C7: Downstream repos use `nixpkgs.follows = "nixpkgs-lock/nixpkgs"` -- zero independent pins
- C8: MIT license
- C9: LLM-generated, validated via CI
- C10: Auto-merge PRs when CI green -- both on nixpkgs-lock and downstream repos
- C11: Zero cross-repo auth in consuming repos -- each repo uses only its own default `GITHUB_TOKEN`
- C12: Adding new downstream repo = add it to the tend loop's fleet, configure `nixpkgs.follows`

## S.I Interfaces

- I.flake: `inputs.nixpkgs` -- sole input, pinned to nixos-26.05 channel
- I.follows: `nixpkgs.follows = "nixpkgs-lock/nixpkgs"` -- how consuming repos reference the pin
- I.pin-refresh: hallucinogen tend loop `pin-refresh` -- opens `hallucinogen/pin-update` PR, drives green, merges
- I.date-badge: README badge text `nixpkgs%20date-YYYY--MM--DD-` -- shields.io doubles a literal dash; the `pin-badge` check derives the expected text from `flake.lock`

## S.W Workflow Implementation

### Pin update (nixpkgs-lock repo -- pin standard)

The hallucinogen tend loop's `pin-refresh` agent action:

1. Runs `nix flake update` on nixpkgs-lock
2. Updates the README nixpkgs date badge to the new `lastModified` date (V7)
3. Opens a `hallucinogen/pin-update` PR if the lock changed
4. Drives the PR green (CI must pass)
5. Merges the PR

nixpkgs-lock settles green before downstream repos are refreshed,
so a broken upstream bump breaks only nixpkgs-lock, not the fleet.

### Pin propagation (each downstream repo)

The tend loop's `pin-refresh` action for downstream repos:

1. Runs `nix flake update nixpkgs-lock` (picks up the validated rev)
2. Runs `nix flake check --no-build`
3. Opens a `hallucinogen/pin-update` PR if the lock changed
4. Drives the PR green and merges

No per-repo cron workflows. No cross-repo tokens in consuming repos.

## S.P Consuming Repo Pattern

### Before (independent pin)

```nix
inputs = {
  nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";
  nix-dev-shell-agentic = {
    url = "github:pr0d1r2/nix-dev-shell-agentic";
    inputs.nixpkgs.follows = "nixpkgs";
  };
};
```

### After (follows nixpkgs-lock)

```nix
inputs = {
  nixpkgs-lock.url = "github:pr0d1r2/nixpkgs-lock";
  nixpkgs.follows = "nixpkgs-lock/nixpkgs";
  nix-dev-shell-agentic = {
    url = "github:pr0d1r2/nix-dev-shell-agentic";
    inputs.nixpkgs.follows = "nixpkgs";
  };
};
```

Key: `nixpkgs` no longer has its own URL -- follows nixpkgs-lock.
`nix-dev-shell-agentic` still gets nixpkgs via the consuming repo's
`follows`, which transitively comes from nixpkgs-lock.

## S.D Downstream Repos

All pr0d1r2/nix-lefthook-* repos (~80), plus:

- nix-dev-shell-agentic
- nix-config-example

Each repo is part of the hallucinogen tend loop's fleet.

## S.V Invariants

- V1: flake.lock always contains exactly one input (nixpkgs)
- V2: nixpkgs always tracks nixos-26.05 channel
- V3: No PR created when `nix flake update` produces no diff (both nixpkgs-lock and downstream)
- V4: All downstream repos resolve to identical nixpkgs rev via follows
- V5: Direct push to main blocked -- PR required
- V6: Zero cross-repo secrets in consuming repos -- no PAT, no dispatch tokens, only default GITHUB_TOKEN per repo
- V7: README nixpkgs date badge matches `flake.lock` `lastModified` (UTC, YYYY-MM-DD) -- enforced by the `pin-badge` check, so a pin refresh that skips the badge fails CI

## S.T Tasks

| id | st | desc | cites |
|----|----|------|-------|
| T1 | x | Minimal flake.nix with nixpkgs 26.05 input | C1,C2,I.flake |
| T2 | x | Generate flake.lock pinning current nixpkgs rev | V1,V2 |
| T3 | x | Create GitHub repo (pr0d1r2/nixpkgs-lock) | C3 |
| T4 | x | Protect main branch, require PRs | C3,V6 |
| T5 | x | CI workflow: `nix flake check` on PRs | C9 |
| T6 | x | Pin updates via hallucinogen tend loop pin-refresh | C4,C5,I.pin-refresh,V3,S.W |
| T7 | x | Flip consuming repos to nixpkgs.follows | C7,V4,S.P |
| T8 | x | Migration to nixos-26.05 channel | C2 |
| T9 | x | README nixpkgs date badge + `pin-badge` drift check | V7 |

## S.B Bugs

| id | date | cause | fix |
|----|------|-------|-----|
| B1 | 2026-07-16 | Migration enabled checks without seeding their required configuration, causing editorconfig, file-size, and embedded-shell validation to fail | Add the canonical set-and-setting check configuration and allowlist |
| B2 | 2026-07-16 | The confirm app validated generated guardrail commands without providing the materialized wrapper packages on its runtime PATH | Include the materialized guardrail package set in the confirm app runtime |
