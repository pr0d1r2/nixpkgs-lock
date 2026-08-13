{
  description = "Centralized nixpkgs version pins for pr0d1r2 Nix ecosystem";

  nixConfig = {
    extra-substituters = [ "https://pr0d1r2.cachix.org" ];
    extra-trusted-public-keys = [ "pr0d1r2.cachix.org-1:NfWjbhgAj41byXhCKiaE+av3Vnphm1fTezHXEGsiQIM=" ];
  };

  # A DEPENDENCY-PROVIDER repo must be a LEAF (#17). This repo publishes the ONE
  # nixpkgs the whole fleet follows, so EVERY repo depends on it; any input
  # declared here re-enters the graph it feeds and multiplies it. Declaring
  # itself plus the standard is what produced 8-16x path multiplicity and a
  # 522,910-byte lock on the pin-refresh branch.
  #
  # So: exactly ONE input, the nixpkgs this repo exists to pin. Guardrails are
  # VENDORED below -- built from that same nixpkgs -- rather than referenced
  # from set-and-setting, because referencing the standard is precisely the edge
  # that must not exist here. A deliberate, narrow exception to the fleet's
  # referenced-guardrails direction, and it applies to PROVIDERS only: a
  # provider cannot consume the graph it feeds.
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";
  };

  outputs =
    { self, nixpkgs }:
    let
      supportedSystems = [
        "aarch64-darwin"
        "x86_64-darwin"
        "x86_64-linux"
        "aarch64-linux"
      ];
      forAllSystems =
        f: nixpkgs.lib.genAttrs supportedSystems (system: f nixpkgs.legacyPackages.${system});

      # Every check is `runCommand src + tools + script`, so a check is exactly
      # one place in this file. Checks run against the flake source, which for a
      # git tree is the TRACKED files only -- result/ and .direnv/ never appear.
      mkCheck =
        pkgs: name: tools: script:
        pkgs.runCommand "${name}-check"
          {
            src = self;
            nativeBuildInputs = tools;
          }
          ''
            cd "$src"
            ${script}
            touch "$out"
          '';
    in
    {
      checks = forAllSystems (pkgs: {
        nixfmt = mkCheck pkgs "nixfmt" [ pkgs.nixfmt-rfc-style ] ''
          find . -name '*.nix' -print0 | xargs -0 -r nixfmt --check
        '';

        statix = mkCheck pkgs "statix" [ pkgs.statix ] ''
          statix check .
        '';

        yamllint = mkCheck pkgs "yamllint" [ pkgs.yamllint ] ''
          find . \( -name '*.yml' -o -name '*.yaml' \) -print0 |
            xargs -0 -r yamllint -c .yamllint.yml
        '';

        markdownlint = mkCheck pkgs "markdownlint" [ pkgs.markdownlint-cli2 ] ''
          markdownlint-cli2 --config .markdownlint.yml '**/*.md'
        '';

        typos = mkCheck pkgs "typos" [ pkgs.typos ] ''
          typos .
        '';

        gitleaks = mkCheck pkgs "gitleaks" [ pkgs.gitleaks ] ''
          gitleaks detect --no-git --source . --redact
        '';

        whitespace = mkCheck pkgs "whitespace" [ ] ''
          rc=0
          while IFS= read -r -d "" f; do
            case "$f" in ./flake.lock | ./LICENSE) continue ;; esac
            if grep -nE ' +$' "$f"; then
              echo "trailing whitespace: $f" >&2
              rc=1
            fi
            if [ -s "$f" ] && [ -n "$(tail -c1 "$f")" ]; then
              echo "missing final newline: $f" >&2
              rc=1
            fi
          done < <(find . -type f ! -path './.git/*' -print0)
          # ⊥ `exit $rc` -- an exit here would skip mkCheck's `touch $out` and
          # fail the build even on a clean pass.
          [ "$rc" -eq 0 ]
        '';

        # The check that caught this repo's own regression: the lock is what
        # blows the limit when the input graph re-enters itself, so it is the
        # one guardrail this flake must never drop. Limits stay in
        # config/lefthook/file_size_limits.yml -- one source of truth, so a
        # ratchet edited there needs no flake change.
        file-size = mkCheck pkgs "file-size" [ pkgs.yq-go ] ''
          cfg=config/lefthook/file_size_limits.yml
          default="$(yq -r '.default' "$cfg")"
          rc=0
          while IFS= read -r -d "" f; do
            ext="''${f##*.}"
            limit="$(yq -r ".extensions.\"$ext\" // \"\"" "$cfg")"
            [ -n "$limit" ] || limit="$default"
            size="$(wc -c <"$f")"
            if [ "$size" -gt "$limit" ]; then
              echo "File size limit exceeded:" >&2
              echo "  - $f: $size bytes > $limit limit ($ext)" >&2
              rc=1
            fi
          done < <(find . -type f ! -path './.git/*' -print0)
          # ⊥ `exit $rc` -- an exit here would skip mkCheck's `touch $out` and
          # fail the build even on a clean pass.
          [ "$rc" -eq 0 ]
        '';
      });

      devShells = forAllSystems (pkgs: {
        default = pkgs.mkShell {
          packages = [
            pkgs.gitleaks
            pkgs.lefthook
            pkgs.markdownlint-cli2
            pkgs.nixfmt-rfc-style
            pkgs.statix
            pkgs.typos
            pkgs.yamllint
            pkgs.yq-go
          ];
        };
      });
    };
}
