{
  description = "nix-scout — frontrunner profile + scout module switcher";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";
    nixpkgs-unstable.url = "github:NixOS/nixpkgs/nixos-unstable";
    home-manager = {
      url = "github:nix-community/home-manager/release-26.05";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    flakelet = {
      url = "github:Mic92/flakelet";
      inputs.nixpkgs.follows = "nixpkgs-unstable";
    };
  };

  outputs = { self, nixpkgs, home-manager, flakelet, ... }: let
    system = "x86_64-linux";
    pkgs = nixpkgs.legacyPackages.${system};
    scoutModuleLib = import ./lib/scout-module.nix;
    scoutScriptPath = pkgs.lib.makeBinPath [
      pkgs.coreutils
      pkgs.diffutils
      pkgs.findutils
      pkgs.jq
    ];
  in {
    lib = scoutModuleLib;

    overlays.default = final: prev: {
      nix-scout = self.packages.${prev.system}.nix-scout;
    };

    # parent: live filesystem path to the host flake root.
    # modulesRel: directory under parent that contains <name>/flake.nix drop-ins.
    # hostInputs: the host (parent) flake's own full, already-resolved `inputs`
    # attrset — threaded through to scout-module eval-time calls so a module's
    # declared inputs (nixpkgs, nix-scout, or anything else the host also
    # declares at top level) resolve identically to what a real `nix build`
    # against the parent-lock-derived flake.lock would give at switch time.
    nixosModule = parent: modulesRel: hostInputs: {
      _file = toString ./nixos-module.nix;
      imports = [
        (import ./nixos-module.nix {
          nixScout = self;
          inherit parent modulesRel flakelet;
          inputs = hostInputs;
        })
      ];
    };

    packages.${system} = {
      nix-scout-plugin = pkgs.callPackage ./plugin/package.nix {
        nix-cmd = pkgs.nix.libs.nix-cmd;
      };

      nix-scout = pkgs.stdenv.mkDerivation {
        pname = "nix-scout";
        version = "0.8.0";
        src = ./.;
        dontBuild = true;
        nativeBuildInputs = [ pkgs.makeWrapper ];
        installPhase = ''
          runHook preInstall
          install -Dm755 $src/bin/nix-scout                $out/bin/nix-scout
          patchShebangs $out/bin/nix-scout
          wrapProgram $out/bin/nix-scout --prefix PATH : ${pkgs.lib.makeBinPath [
            pkgs.bash
            pkgs.coreutils
            pkgs.findutils
            pkgs.gnugrep
            pkgs.nix
            pkgs.getent
          ]}
          # PATH shim for `nix scout` (CppNix loads plugins after subcommand
          # resolution; the NixOS module installs this as a hiPrio `nix`).
          install -Dm755 $src/bin/nix-wrap.sh $out/bin/nix-wrap
          substituteInPlace $out/bin/nix-wrap \
            --replace-fail '@real_nix@' '${pkgs.nix}/bin/nix' \
            --replace-fail '@nix_scout@' "$out/bin/nix-scout"
          install -Dm755 $src/lib/materialize-module.sh  $out/lib/materialize-module.sh
          install -Dm644 $src/lib/scout-lib.sh           $out/lib/scout-lib.sh
          install -Dm644 $src/lib/scout-module.nix       $out/lib/scout-module.nix
          install -Dm644 $src/lib/module-adapters.nix    $out/lib/module-adapters.nix
          install -Dm755 $src/lib/new-module.sh          $out/lib/new-module.sh
          install -Dm755 $src/lib/update-module.sh       $out/lib/update-module.sh
          install -Dm755 $src/lib/apply-hm.sh            $out/lib/apply-hm.sh
          install -Dm755 $src/lib/apply-env.sh           $out/lib/apply-env.sh
          install -Dm755 $src/lib/apply-flakelet.sh      $out/lib/apply-flakelet.sh
          install -Dm755 $src/lib/flakelet-access.sh     $out/lib/flakelet-access.sh
          install -Dm755 $src/lib/hm-activate-files.sh   $out/lib/hm-activate-files.sh
          patchShebangs $out/lib
          for script in apply-hm.sh hm-activate-files.sh; do
            wrapProgram $out/lib/$script --prefix PATH : ${scoutScriptPath}
          done
          install -Dm644 $src/share/man/man1/nix-scout.1 \
            $out/share/man/man1/nix-scout.1
          install -Dm644 $src/share/subcommands.tsv \
            $out/share/nix-scout/subcommands.tsv
          mkdir -p $out/share/fish/vendor_completions.d
          bash $out/bin/nix-scout completions fish \
            > $out/share/fish/vendor_completions.d/nix-scout.fish
          mkdir -p $out/share/bash-completion/completions
          bash $out/bin/nix-scout completions bash \
            > $out/share/bash-completion/completions/nix-scout
          # nixpkgs zsh adds $out/share/zsh/site-functions to fpath (see pkgs.zsh).
          mkdir -p $out/share/zsh/site-functions
          bash $out/bin/nix-scout completions zsh \
            > $out/share/zsh/site-functions/_nix-scout
          runHook postInstall
        '';
        meta = {
          description = "nix-scout — scout module switcher";
          license = pkgs.lib.licenses.mit;
          mainProgram = "nix-scout";
        };
      };
    };

    checks.${system} = {
      static-contracts = pkgs.runCommand "nix-scout-static-contracts"
        { buildInputs = [ pkgs.bash pkgs.gnugrep pkgs.coreutils pkgs.findutils pkgs.diffutils pkgs.gawk ]; }
        ''
          cp -r ${./.} "$TMPDIR/nix-scout-source"
          chmod -R u+w "$TMPDIR/nix-scout-source"
          patchShebangs "$TMPDIR/nix-scout-source/bin" "$TMPDIR/nix-scout-source/lib" \
            "$TMPDIR/nix-scout-source/tests"
          export NIX_SCOUT_ROOT="$TMPDIR/nix-scout-source"
          export USER=nix-scout-test
          export HOME="$TMPDIR/home"
          # Run from one writable whole-repo copy so sibling test fixtures are
          # present and executable scripts have sandbox-valid shebangs.
          bash "$NIX_SCOUT_ROOT/tests/module-mode.sh"
          bash "$NIX_SCOUT_ROOT/tests/path-session.sh"
          bash "$NIX_SCOUT_ROOT/tests/activation-clear.sh"
          bash "$NIX_SCOUT_ROOT/tests/activation-home-files.sh"
          bash "$NIX_SCOUT_ROOT/tests/flakelet.sh"
          bash "$NIX_SCOUT_ROOT/tests/completions.sh"
          bash "$NIX_SCOUT_ROOT/tests/plugin-shim.sh"
          touch $out
        '';

      # Plugin builds against pkgs.nix (in-range).
      plugin = self.packages.${system}.nix-scout-plugin;

      # Out-of-range minor must fail to compile (#error in version.hh).
      plugin-version-gate = pkgs.runCommand "nix-scout-plugin-version-gate" {
        nativeBuildInputs = [ pkgs.pkg-config pkgs.stdenv.cc pkgs.nlohmann_json ];
        buildInputs = [ pkgs.nix.libs.nix-cmd ];
      } ''
        cp ${./plugin/scout.cc} scout.cc
        cp ${./plugin/version.hh} version.hh
        set +e
        $CXX -std=c++23 -shared -fPIC scout.cc -o /dev/null \
          $(pkg-config --cflags nix-cmd) \
          -DNIX_SCOUT_PLUGIN_NIX_MAJOR=2 \
          -DNIX_SCOUT_PLUGIN_NIX_MINOR=33 \
          -Wl,--unresolved-symbols=ignore-all 2>err-low.txt
        rc_low=$?
        $CXX -std=c++23 -shared -fPIC scout.cc -o /dev/null \
          $(pkg-config --cflags nix-cmd) \
          -DNIX_SCOUT_PLUGIN_NIX_MAJOR=2 \
          -DNIX_SCOUT_PLUGIN_NIX_MINOR=36 \
          -Wl,--unresolved-symbols=ignore-all 2>err-high.txt
        rc_high=$?
        set -e
        grep -q 'below the supported range' err-low.txt
        grep -q 'above the supported range' err-high.txt
        test "$rc_low" -ne 0
        test "$rc_high" -ne 0
        echo pass > $out
      '';

      module-adapters = import ./tests/module-adapters.nix {
        inherit nixpkgs home-manager;
        nixScout = self;
      };

      host-module = import ./tests/host-module.nix {
        inherit nixpkgs home-manager flakelet;
        nixScout = self;
      };
    };

    devShells.${system}.default = pkgs.mkShell {
      packages = with pkgs; [
        nix
        bash
        shellcheck
        jq
        bubblewrap
        coreutils
        diffutils
        findutils
        gnugrep
      ];

      shellHook = ''
        echo "nix-scout dev — commands: ns-test, ns-sandbox"

        ns-test() {
          local suite="''${1:-all}"
          local tests_dir="''${NIX_SCOUT_TESTS:-$(dirname "$(readlink -f "''${BASH_SOURCE[0]:-$0}")")/tests}"
          if [[ "$suite" == "all" ]]; then
            for f in "$tests_dir"/*.sh; do
              [[ -x "$f" ]] || continue
              echo "==> ''${f##*/}"
              bash "$f"
            done
          else
            bash "$tests_dir/$suite.sh"
          fi
        }

        # Run a command inside a nix-scout sandbox: tmpfs replaces the per-user
        # nix profile and gcroots directories so operations are fully isolated.
        ns-sandbox() {
          local _tmp
          _tmp="$(mktemp -d)"
          mkdir -p \
            "$_tmp/profiles/per-user/$USER" \
            "$_tmp/gcroots/per-user/$USER"
          bwrap \
            --dev-bind / / \
            --tmpfs /tmp \
            --bind "$_tmp/profiles" /nix/var/nix/profiles/per-user \
            --bind "$_tmp/gcroots"  /nix/var/nix/gcroots/per-user \
            --die-with-parent \
            -- "''${@:-$SHELL}"
          rm -rf "$_tmp"
        }
      '';
    };
  };
}
