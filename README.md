# nixpkgs-lock

<!-- hallucinogen:autonomy-disclaimer start -->
> Read [LLM-DISCLAIMER](docs/LLM-DISCLAIMER.md) first — this repository is
> tended by an autonomous loop, and that file says what the loop may do here,
> what it may not, and what to check before trusting anything in this tree.
<!-- hallucinogen:autonomy-disclaimer end -->

[![CI](https://github.com/pr0d1r2/nixpkgs-lock/actions/workflows/ci.yml/badge.svg)](https://github.com/pr0d1r2/nixpkgs-lock/actions/workflows/ci.yml)
[![nixpkgs](https://img.shields.io/badge/nixpkgs-nixos--26.05-blue)](https://github.com/NixOS/nixpkgs/tree/nixos-26.05)
[![nixpkgs rev](https://img.shields.io/badge/dynamic/json?url=https%3A%2F%2Fraw.githubusercontent.com%2Fpr0d1r2%2Fnixpkgs-lock%2Fmain%2Fflake.lock&query=%24.nodes.nixpkgs.locked.rev&label=nixpkgs%20rev&color=green)](https://github.com/pr0d1r2/nixpkgs-lock/blob/main/flake.lock)
[![nixpkgs date](https://img.shields.io/badge/nixpkgs%20date-2026--09--03-blue)](https://github.com/pr0d1r2/nixpkgs-lock/blob/main/flake.lock)

Centralized nixpkgs version pin for all pr0d1r2/nix-* repos.

## Usage

```nix
inputs = {
  nixpkgs-lock.url = "github:pr0d1r2/nixpkgs-lock";
  nixpkgs.follows = "nixpkgs-lock/nixpkgs";
};
```

## How it works

- Single `flake.lock` pins nixpkgs for ~80 downstream repos
- The hallucinogen tend loop's `pin-refresh` runs `nix flake update`, opens a PR, drives it green, and merges
- nixpkgs-lock is bumped first as the pin standard — downstream repos refresh to the validated rev
- All repos resolve to identical nixpkgs rev via `follows`
- The nixpkgs date badge is the `lastModified` of the pinned rev; `nix/hooks/post-pin-update.sh` writes it after a lock bump and the `pin-badge` check fails CI if it is ever left stale

See [SPEC.md](SPEC.md) for full specification.
