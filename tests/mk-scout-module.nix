{ nixpkgs, nixScout }:

let
  system = "x86_64-linux";
  pkgs = nixpkgs.legacyPackages.${system};
  mkScoutModule = nixScout.lib.mkScoutModule;

  facets = {
    baseline = { necessary, ... }:
      { baseline = { _module.args.mkScoutTestMarker =
          if builtins.isString necessary.pkgs.hello then "supplied" else "fallback";
        }; };

    home = { necessary, ... }:
      { homeBaseline = { _module.args.mkScoutTestMarker =
          if builtins.isString necessary.pkgs.hello then "supplied" else "fallback";
        }; };

    scout = { necessary, ... }:
      { packages.${system}.scout = necessary.pkgs.hello; };

    flakelet = { args, ... }:
      { flakelets.default = { _testMode = args.mode; }; };
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
