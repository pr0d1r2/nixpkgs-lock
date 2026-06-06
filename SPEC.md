# SPEC -- nixpkgs-lock

## S.G Goal

Centralized nixpkgs version pin for all pr0d1r2/nix-* repos. Single flake.lock is source of truth. Daily cron updates nixpkgs pin. Downstream repos pull updates on their own cron -- no cross-repo auth, no central registry, fully decentralized propagation. No manual intervention on happy path.

## S.C Constraints

- C1: Minimal flake -- inputs only, no outputs, no code
- C2: Pin nixpkgs stable channel (nixos-25.11, planned migration to 26.05)
- C3: Main branch protected -- all changes via PR
- C4: Daily cron at 06:00 UTC -- `nix flake update`, PR if lock changed
- C5: Pull model -- downstream repos poll nixpkgs-lock on their own cron, no cross-repo tokens
- C6: No-op safe -- if nixpkgs-lock rev unchanged, `nix flake update nixpkgs-lock` produces no diff, no PR created
- C7: Downstream repos use `nixpkgs.follows = "nixpkgs-lock/nixpkgs"` -- zero independent pins
- C8: MIT license
- C9: LLM-generated, validated via CI
- C10: Auto-merge PRs when CI green -- both on nixpkgs-lock and downstream repos
- C11: Zero cross-repo auth -- each repo uses only its own default `GITHUB_TOKEN`
- C12: Self-contained -- adding new downstream repo = add cron workflow to that repo, no central config change

## S.I Interfaces

- I.flake: `inputs.nixpkgs` -- sole input, pinned to nixos-25.11 channel
- I.follows: `nixpkgs.follows = "nixpkgs-lock/nixpkgs"` -- how consuming repos reference the pin
- I.cron: `.github/workflows/daily-update.yml` -- daily `nix flake update` + auto-PR (nixpkgs-lock repo)
- I.pull: `.github/workflows/update-pins.yml` -- downstream repo cron polling nixpkgs-lock for changes

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

### Pull update (each downstream repo)

```yaml
# .github/workflows/update-pins.yml
on:
  schedule:
    - cron: '30 6 * * *'  # 30min after nixpkgs-lock cron
steps:
  - uses: actions/checkout@v4
  - uses: cachix/install-nix-action@v27
  - run: nix flake update nixpkgs-lock
  - run: nix flake check --no-build
  - uses: peter-evans/create-pull-request@v6
    with:
      commit-message: "chore: update nixpkgs-lock pin"
      title: "chore: update nixpkgs-lock pin"
      branch: auto/pin-update
      delete-branch: true
```

No cross-repo tokens. Each repo uses default `GITHUB_TOKEN`. No central registry. No propagation workflow. Adding new repo = add this workflow to it.

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

Each repo is self-contained -- owns its own cron workflow, no central list needed.

## S.V Invariants

- V1: flake.lock always contains exactly one input (nixpkgs)
- V2: nixpkgs always tracks nixos-25.11 channel (until 26.05 migration)
- V3: No PR created when `nix flake update` produces no diff (both nixpkgs-lock and downstream)
- V4: All downstream repos resolve to identical nixpkgs rev via follows
- V5: Direct push to main blocked -- PR required
- V6: Zero cross-repo secrets -- no PAT, no dispatch tokens, only default GITHUB_TOKEN per repo

## S.T Tasks

| id | st | desc | cites |
|----|----|------|-------|
| T1 | x | Minimal flake.nix with nixpkgs 25.11 input | C1,C2,I.flake |
| T2 | x | Generate flake.lock pinning current nixpkgs rev | V1,V2 |
| T3 | x | Create GitHub repo (pr0d1r2/nixpkgs-lock) | C3 |
| T4 | x | Protect main branch, require PRs | C3,V6 |
| T5 | . | Daily update workflow (cron + auto-PR) | C4,C10,I.cron,V3,S.W |
| T6 | . | CI workflow: `nix flake check` on PRs | C9 |
| T7 | . | Add pull-update cron workflow to downstream repos | C5,C12,I.pull,S.W |
| T8 | . | Flip consuming repos to nixpkgs.follows | C7,V4,S.P |
| T9 | . | Migration to nixos-26.05 channel | C2 |

## S.B Bugs

(none yet)
