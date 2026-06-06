# SPEC -- nixpkgs-lock

## S.G Goal

Centralized nixpkgs version pin for all pr0d1r2/nix-* repos. Single flake.lock is source of truth. Daily cron updates nixpkgs, event-driven dispatch propagates to downstream repos. No manual intervention on happy path.

## S.C Constraints

- C1: Minimal flake -- inputs only, no outputs, no code
- C2: Pin nixpkgs stable channel (nixos-25.11, planned migration to 26.05)
- C3: Main branch protected -- all changes via PR
- C4: Daily cron at 06:00 UTC -- `nix flake update`, PR if lock changed
- C5: Event-driven propagation -- `repository_dispatch` to downstream repos only on lock change
- C6: No dispatch on no-op days -- if nixpkgs rev unchanged, nothing fires
- C7: Downstream repos use `nixpkgs.follows = "nixpkgs-lock/nixpkgs"` -- zero independent pins
- C8: MIT license
- C9: LLM-generated, validated via CI

## S.I Interfaces

- I.flake: `inputs.nixpkgs` -- sole input, pinned to nixos-25.11 channel
- I.follows: `nixpkgs.follows = "nixpkgs-lock/nixpkgs"` -- how consuming repos reference the pin
- I.cron: `.github/workflows/daily-update.yml` -- daily `nix flake update` + auto-PR
- I.dispatch: `.github/workflows/propagate.yml` -- post-merge `repository_dispatch` to downstream repos
- I.registry: `downstream-repos.txt` -- newline-delimited list of repos to notify on update

## S.V Invariants

- V1: flake.lock always contains exactly one input (nixpkgs)
- V2: nixpkgs always tracks nixos-25.11 channel (until 26.05 migration)
- V3: No PR created when `nix flake update` produces no diff
- V4: Dispatch fires only on push to main with flake.lock change
- V5: All downstream repos resolve to identical nixpkgs rev via follows
- V6: Direct push to main blocked -- PR required

## S.T Tasks

| id | st | desc | cites |
|----|----|------|-------|
| T1 | x | Minimal flake.nix with nixpkgs 25.11 input | C1,C2,I.flake |
| T2 | x | Generate flake.lock pinning current nixpkgs rev | V1,V2 |
| T3 | x | Create GitHub repo (pr0d1r2/nixpkgs-lock) | C3 |
| T4 | x | Protect main branch, require PRs | C3,V6 |
| T5 | . | Daily update workflow (cron + auto-PR) | C4,C6,I.cron,V3 |
| T6 | . | Propagation workflow (dispatch on merge) | C5,I.dispatch,V4 |
| T7 | . | downstream-repos.txt registry | I.registry |
| T8 | . | Flip consuming repos to nixpkgs.follows | C7,V5 |
| T9 | . | CI workflow: `nix flake check` on PRs | C9 |
| T10 | . | Migration to nixos-26.05 channel | C2 |

## S.B Bugs

(none yet)
