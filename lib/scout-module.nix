# Helpers for scout-module flakes (packages.<system>.scout).
#
# Scout modules read build mode, resolved settings, and switch user identity
# from readContext. The mode remains available on its own through:
#   systemRebuild = true  — NixOS rebuild prebuild (environment.systemPackages)
#   systemRebuild = false — `nix-scout switch` (ephemeral profile; cleared on boot/clear)
#
# In flake.nix (moduleRoot is usually ./.):
#   outputs = args: let
#     systemRebuild = (import <nix-scout/lib/scout-module.nix>).readSystemRebuild ./. args;
#   in { ... };

let
  adapters = import ./module-adapters.nix;
in
rec {
  # Build the facet-separated output contract for a scout module.
  #
  # `inputs.pkgs` is supplied by the host NixOS adapter when the module is
  # evaluated as part of a system rebuild. Standalone module evaluation does
  # not have that value, so retain the historical fallback import there.
  # `inputs ? nix-scout` remains an implementation detail of the evaluation
  # mode; callers only need to provide the four facet functions.
  mkScoutModule = inputs: facets:
    let
      isScoutEval = inputs ? nix-scout;
      system = inputs.system or "x86_64-linux";
      pkgs =
        if inputs ? pkgs && inputs.pkgs != null
        then inputs.pkgs
        else import inputs.nixpkgs { inherit system; };
      all = inputs;
      args = {
        inherit system isScoutEval;
        mode = if isScoutEval then "nix-scout" else "flakelet";
        systemRebuild = inputs.systemRebuild or false;
      };
      necessary = {
        inherit pkgs;
        lib = pkgs.lib;
      };
      call = name: facets.${name} { inherit all args necessary; };
      facet = name:
        if facets ? ${name}
        then call name
        else { };
    in
      (if isScoutEval
       then facet "baseline" // facet "home" // facet "scout"
       else { })
      // facet "flakelet";

  readContext = moduleRoot: args:
    let
      contextFile = moduleRoot + "/scout-context.nix";
    in
      args.scoutContext or (
        if builtins.pathExists contextFile
        then import contextFile
        else {
          version = 1;
          mode = if args.systemRebuild or false then "rebuild" else "standalone";
          systemRebuild = args.systemRebuild or false;
        }
      );

  readSystemRebuild = moduleRoot: args:
    (if args ? systemRebuild
    then args.systemRebuild
    else (readContext moduleRoot args).systemRebuild);

  nixosModule = adapters.nixosModule;
  homeManagerModule = adapters.homeManagerModule;
}
