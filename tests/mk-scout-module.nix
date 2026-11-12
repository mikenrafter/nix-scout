{ nixpkgs, nixScout }:

let
  system = "x86_64-linux";
  pkgs = nixpkgs.legacyPackages.${system};
  mkScoutModule = nixScout.lib.mkScoutModule;

  facets = {
    baseline = { pkgs, ... }:
      { baseline = { _module.args.mkScoutTestMarker =
          if builtins.isString pkgs.hello then "supplied" else "fallback";
        }; };

    home = { pkgs, ... }:
      { homeBaseline = { _module.args.mkScoutTestMarker =
          if builtins.isString pkgs.hello then "supplied" else "fallback";
        }; };

    scout = { pkgs, ... }:
      { packages.${system}.scout = pkgs.hello; };

    flakelet = { mode, ... }:
      { flakelets.default = { _testMode = mode; }; };
  };

  supplied = mkScoutModule ./.
    ({
      inherit nixpkgs system;
      nix-scout = nixScout;
      pkgs = pkgs // { hello = "supplied"; };
      systemRebuild = true;
    })
    facets;

  fallback = mkScoutModule ./.
    ({
      inherit nixpkgs system;
      nix-scout = nixScout;
      systemRebuild = true;
    })
    facets;

  flakelet = mkScoutModule ./. { inherit nixpkgs system; } facets;

  # A standalone `nix-scout switch` passes no system and no pkgs: every
  # supported Linux system must get its own scout package (aarch64 hosts).
  # Settings arrive only through scout-context.nix, as in a real switch.
  perSystem = mkScoutModule ./fixtures/switch-context
    {
      inherit nixpkgs;
      nix-scout = nixScout;
    }
    (facets // { scout = { system, scoutContext ? { }, ... }: {
      packages.${system}.scout = "${system}:${builtins.toJSON (scoutContext.settings.flag or false)}";
    }; });
in
assert supplied.baseline._module.args.mkScoutTestMarker == "supplied";
assert fallback.baseline._module.args.mkScoutTestMarker == "fallback";
assert builtins.hasAttr "packages" supplied;
assert builtins.hasAttr "homeBaseline" supplied;
assert builtins.hasAttr "flakelets" supplied;
assert builtins.attrNames flakelet == [ "flakelets" ];
assert flakelet.flakelets.default._testMode == "flakelet";
assert builtins.attrNames perSystem.packages == [ "aarch64-linux" "x86_64-linux" ];
assert perSystem.packages.aarch64-linux.scout == "aarch64-linux:true";
assert perSystem.packages.x86_64-linux.scout == "x86_64-linux:true";
"pass"
