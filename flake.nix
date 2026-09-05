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
      inherit (nixpkgs) lib;
      forAllSystems = f: lib.genAttrs supportedSystems (system: f nixpkgs.legacyPackages.${system});

      # Guardrail shell lives in nix/check/*.sh so it stays a REAL script:
      # executable, shellcheck-clean, unit-testable, runnable by hand. The flake
      # reads it at EVAL time and keeps only the body -- the standalone preamble
      # (shebang, header comment, `set`) must not survive, because mkCheck
      # already supplies the shell. Reading rather than invoking is also what
      # makes the check a pure derivation: the body is baked into the .drv
      # instead of being located under $src when the builder runs.
      scriptBody =
        path:
        let
          lines = lib.splitString "\n" (builtins.readFile path);
          isPreamble = l: l == "" || lib.hasPrefix "#" l || lib.hasPrefix "set -" l;
          body = lib.lists.findFirstIndex (l: !isPreamble l) (lib.length lines) lines;
        in
        lib.concatStringsSep "\n" (lib.drop body lines);

      # Guardrail logic shared with the fleet is fetched by COMMIT and hash
      # rather than taken as a flake input (V9). Those repos declare
      # `nixpkgs-lock.url`, so an input edge from here would be cyclic and
      # would rebuild the multiplicity #17 removed. A fetchurl is a
      # fixed-output derivation: no node in flake.lock, no second nixpkgs in
      # the graph, so the leaf invariant holds while the logic stays shared
      # with the ~80 repos running the same scripts.
      #
      # The pin is a COMMIT, never a branch or tag: fetchurl demands a hash,
      # and anything movable breaks the build at whatever moment upstream next
      # edits the file, on an unrelated PR.
      fleetScript =
        pkgs:
        {
          repo,
          rev,
          file,
          hash,
        }:
        builtins.readFile (
          pkgs.fetchurl {
            url = "https://raw.githubusercontent.com/pr0d1r2/${repo}/${rev}/${file}";
            inherit hash;
          }
        );

      trailingWhitespace =
        pkgs:
        pkgs.writeShellApplication {
          name = "lefthook-trailing-whitespace";
          runtimeInputs = [
            pkgs.coreutils
            pkgs.gnugrep
          ];
          text = fleetScript pkgs {
            repo = "nix-lefthook-trailing-whitespace";
            rev = "3755028f3691b4e04b05881da16d350acd268523";
            file = "lefthook-trailing-whitespace.sh";
            hash = "sha256-zdI3pUndL4GySkUfnHWaY8+JoJoBBgmIzEFI9SFn2SU=";
          };
        };

      # Two files: the checker shells out to `get-file-size-limit` as a command
      # on PATH, so the helper is packaged separately and fed to the checker's
      # runtimeInputs -- the same wiring upstream's own flake uses.
      fileSizeCheck =
        pkgs:
        let
          rev = "f30fa4c19aaf68f1e9ad831d2b8e62863a3b6eb0";
          getLimit = pkgs.writeShellApplication {
            name = "get-file-size-limit";
            runtimeInputs = [
              pkgs.gawk
              pkgs.gnugrep
            ];
            text = fleetScript pkgs {
              repo = "nix-lefthook-file-size-check";
              inherit rev;
              file = "get-file-size-limit.sh";
              hash = "sha256-MTwV/UlHBGjNliX38pC2b4Vgw9EbTwClz12uzT7oqFk=";
            };
          };
        in
        pkgs.writeShellApplication {
          name = "lefthook-file-size-check";
          runtimeInputs = [
            pkgs.coreutils
            pkgs.gawk
            pkgs.gnugrep
            getLimit
          ];
          text = fleetScript pkgs {
            repo = "nix-lefthook-file-size-check";
            inherit rev;
            file = "lefthook-file-size-check.sh";
            hash = "sha256-2gwtAdSeF145ZjTCWZkCN64AB/+BsKl95MMlqWoMeB4=";
          };
        };

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

        # The tool takes file arguments, lefthook-style, so the tree scan
        # lives here. $src carries tracked files only -- no .git, no result/,
        # no .direnv -- so nothing needs pruning. flake.lock and LICENSE used
        # to be exempt; both pass the tool as-is, so the exemptions are gone
        # and the coverage is wider than before.
        whitespace = mkCheck pkgs "whitespace" [ (trailingWhitespace pkgs) ] ''
          find . -type f -print0 | xargs -0 -r lefthook-trailing-whitespace
        '';

        # nix/check/*.sh are real scripts so they can be tested as real
        # scripts: the suite runs each against throwaway fixtures in a temp
        # directory, never the repo's own flake.lock and README.md.
        #
        # tests/unit MIRRORS the source tree -- tests/unit/nix/check/x.bats
        # covers nix/check/x.sh -- so `bats` needs --recursive to reach them.
        bats =
          mkCheck pkgs "bats"
            [
              pkgs.bats
              pkgs.jq
              pkgs.coreutils
              # The UTC case sets TZ to a real zone; without the database
              # `date` falls back to UTC anyway and the test loses its teeth.
              pkgs.tzdata
            ]
            ''
              bats --recursive tests/unit
            '';

        shellcheck = mkCheck pkgs "shellcheck" [ pkgs.shellcheck ] ''
          find . -name '*.sh' -print0 | xargs -0 -r shellcheck
        '';

        pin-badge = mkCheck pkgs "pin-badge" [
          pkgs.jq
          pkgs.coreutils
        ] (scriptBody ./nix/check/pin_badge.sh);

        # The check that caught this repo's own regression: the lock is what
        # blows the limit when the input graph re-enters itself, so it is the
        # one guardrail this flake must never drop. Limits stay in
        # config/lefthook/file_size_limits.yml, the path the tool defaults to,
        # so a ratchet edited there needs no flake change.
        file-size = mkCheck pkgs "file-size" [ (fileSizeCheck pkgs) ] ''
          find . -type f -print0 | xargs -0 -r lefthook-file-size-check
        '';
      });

      devShells = forAllSystems (pkgs: {
        default = pkgs.mkShell {
          packages = [
            pkgs.bats
            pkgs.gitleaks
            pkgs.jq
            pkgs.lefthook
            (fileSizeCheck pkgs)
            (trailingWhitespace pkgs)
            pkgs.markdownlint-cli2
            pkgs.nixfmt-rfc-style
            pkgs.shellcheck
            pkgs.statix
            pkgs.typos
            pkgs.yamllint
            pkgs.yq-go
          ];
        };
      });
    };
}
