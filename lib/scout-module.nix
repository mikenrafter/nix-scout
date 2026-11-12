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
  # Each facet function has the same shape as an ordinary flake `outputs`
  # function: it receives every input this module declares, by name, plus
  # `pkgs`/`system`/`lib` (and `isScoutEval`/`mode`/`systemRebuild`) merged
  # in alongside them — e.g. `scout = { nixpkgs, pkgs, system, break-lock,
  # ... }@args: {...}`. No separate namespaced buckets to remember; it's the
  # normal `outputs = inputs: ...` convention with a few extra keys added.
  #
  # `pkgs` is supplied by the host NixOS adapter (as `inputs.pkgs`) when the
  # module is evaluated as part of a system rebuild. Standalone module
  # evaluation does not have that value, so retain the historical fallback
  # import there. Facet gating uses scout-context (rebuild/switch vs
  # standalone flakelet eval); callers pass ./. as moduleRoot and declare
  # inputs.nix-scout for this helper.
  # moduleRoot is usually ./. — used to read scout-context.nix during switch builds.
  #
  # A standalone `nix-scout switch` passes neither `system` nor host `pkgs`.
  # The module is then built for every supported Linux system, so an aarch64
  # host finds `packages.aarch64-linux.scout` (each system's pkgs is imported
  # only when that attribute is forced). A rebuild hands over the host's pkgs
  # and keeps the single-system result.
  mkScoutModule = moduleRoot: inputs: facets:
    if inputs ? system || (inputs.pkgs or null) != null
    then mkScoutModuleFor moduleRoot inputs facets (inputs.system or "x86_64-linux")
    else
      let
        x86 = mkScoutModuleFor moduleRoot inputs facets "x86_64-linux";
        arm = mkScoutModuleFor moduleRoot inputs facets "aarch64-linux";
      in
        x86 // { packages = (x86.packages or { }) // (arm.packages or { }); };

  mkScoutModuleFor = moduleRoot: inputs: facets: system:
    let
      context = readContext moduleRoot inputs;
      isScoutEval =
        inputs.systemRebuild or false
        || context.mode == "rebuild"
        || context.mode == "switch";
      pkgs =
        if inputs ? pkgs && inputs.pkgs != null
        then inputs.pkgs
        else import inputs.nixpkgs { inherit system; };
      # Facets read resolved settings from scoutContext; a switch only has
      # them in scout-context.nix, so pass the context along.
      callArgs = inputs // {
        inherit system pkgs isScoutEval;
        scoutContext = context;
        mode = if isScoutEval then "nix-scout" else "flakelet";
        systemRebuild = inputs.systemRebuild or false;
        lib = pkgs.lib;
      };
      call = name: facets.${name} callArgs;
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
