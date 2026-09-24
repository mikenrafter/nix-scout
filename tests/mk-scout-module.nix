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

  supplied = mkScoutModule
    {
      inherit nixpkgs system;
      nix-scout = nixScout;
      pkgs = pkgs // { hello = "supplied"; };
    }
    facets;

  fallback = mkScoutModule
    {
      inherit nixpkgs system;
      nix-scout = nixScout;
    }
    facets;

  flakelet = mkScoutModule { inherit nixpkgs system; } facets;
in
assert supplied.baseline._module.args.mkScoutTestMarker == "supplied";
assert fallback.baseline._module.args.mkScoutTestMarker == "fallback";
assert builtins.hasAttr "packages" supplied;
assert builtins.hasAttr "homeBaseline" supplied;
assert builtins.hasAttr "flakelets" supplied;
assert builtins.attrNames flakelet == [ "flakelets" ];
assert flakelet.flakelets.default._testMode == "flakelet";
"pass"
