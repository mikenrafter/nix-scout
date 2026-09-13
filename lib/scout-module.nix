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

  inherit (adapters) nixosModule homeManagerModule;
}
