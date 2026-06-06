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
- C10: Auto-merge PRs when CI green -- both on nixpkgs-lock and downstream repos
- C11: `DISPATCH_TOKEN` secret -- PAT with `repo` scope for cross-repo dispatch
- C12: Downstream repos need receiver workflow for `repository_dispatch` event type `pins-updated`

## S.I Interfaces

- I.flake: `inputs.nixpkgs` -- sole input, pinned to nixos-25.11 channel
- I.follows: `nixpkgs.follows = "nixpkgs-lock/nixpkgs"` -- how consuming repos reference the pin
- I.cron: `.github/workflows/daily-update.yml` -- daily `nix flake update` + auto-PR
- I.dispatch: `.github/workflows/propagate.yml` -- post-merge `repository_dispatch` to downstream repos
- I.registry: `downstream-repos.txt` -- newline-delimited list of repos to notify on update
- I.receiver: `.github/workflows/update-pins.yml` -- downstream repo workflow reacting to `pins-updated` dispatch

## S.W Workflow Implementation

### Daily update (nixpkgs-lock repo)

```yaml
# .github/workflows/daily-update.yml
on:
  schedule:
    - cron: '0 6 * * *'
steps:
  - uses: actions/checkout@v4
  - uses: cachix/install-nix-action@v27
  - run: nix flake update
  - uses: peter-evans/create-pull-request@v6
    with:
      commit-message: "chore: daily nixpkgs pin update"
      title: "chore: daily nixpkgs pin update"
      branch: auto/daily-update
      delete-branch: true
```

### Propagation (nixpkgs-lock repo, post-merge)

```yaml
# .github/workflows/propagate.yml
on:
  push:
    branches: [main]
    paths: [flake.lock]
steps:
  - uses: actions/checkout@v4
  - run: |
      while read repo; do
        gh api "repos/pr0d1r2/$repo/dispatches" \
          -f event_type=pins-updated
      done < downstream-repos.txt
    env:
      GH_TOKEN: ${{ secrets.DISPATCH_TOKEN }}
```

### Receiver (each downstream repo)

```yaml
# .github/workflows/update-pins.yml
on:
  repository_dispatch:
    types: [pins-updated]
steps:
  - uses: actions/checkout@v4
  - uses: cachix/install-nix-action@v27
  - run: nix flake update nixpkgs-lock
  - run: nix flake check --no-build
  - uses: peter-evans/create-pull-request@v6
    with:
      commit-message: "chore: update nixpkgs-lock pins"
      title: "chore: update nixpkgs-lock pins"
      branch: auto/pin-update
      delete-branch: true
```

## S.P Consuming Repo Pattern

### Before (independent pin)

```nix
inputs = {
  nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.11";
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

Key: `nixpkgs` no longer has its own URL -- follows nixpkgs-lock. `nix-dev-shell-agentic` still gets nixpkgs via the consuming repo's `follows`, which transitively comes from nixpkgs-lock.

## S.D Downstream Repos

All pr0d1r2/nix-lefthook-* repos (~80), plus:
- nix-dev-shell-agentic
- nix-config-example

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
| T5 | . | Daily update workflow (cron + auto-PR) | C4,C6,C10,I.cron,V3,S.W |
| T6 | . | Propagation workflow (dispatch on merge) | C5,C11,I.dispatch,V4,S.W |
| T7 | . | downstream-repos.txt registry | I.registry,S.D |
| T8 | . | Add receiver workflow to downstream repos | C12,I.receiver,S.W |
| T9 | . | Flip consuming repos to nixpkgs.follows | C7,V5,S.P |
| T10 | . | CI workflow: `nix flake check` on PRs | C9 |
| T11 | . | Configure DISPATCH_TOKEN secret | C11 |
| T12 | . | Migration to nixos-26.05 channel | C2 |

## S.B Bugs

(none yet)
