{ nixpkgs, home-manager, flakelet, nixScout }:

let
  system = "x86_64-linux";
  lib = nixpkgs.lib;
  host = lib.nixosSystem {
    inherit system;
    specialArgs.self = ./adapter-host;
    modules = [
      home-manager.nixosModules.home-manager
      (import ../nixos-module.nix {
        inherit flakelet;
        nixScout = nixScout;
        parent = "/tmp/nix-scout-adapter-host";
        modulesRel = "scout-modules";
        inputs = {
          inherit nixpkgs home-manager flakelet;
          nix-scout = nixScout;
        };
      })
      {
        system.stateVersion = "26.05";
        users.users.fixture = {
          isNormalUser = true;
          home = "/home/fixture";
        };
        home-manager.users.fixture = {
          home.stateVersion = "26.05";
        };
      }
    ];
  };
  scoutPackage = lib.findFirst
    (package: package.name == "scout-home-manager-files")
    (throw "missing adapted Home Manager scout package")
    host.config.environment.systemPackages;
in
assert host.config.home-manager.users.fixture.home.sessionVariables.NIX_SCOUT_ADAPTER_HOST == "present";
assert host.config.environment.etc."fixture-support".text == "baseline";
assert host.config.systemd.services.fixture.enable == false;
assert host.config.services.flakelets.services ? fixture;
assert builtins.readFile "${scoutPackage}/home-files/.config/fixture/message" == "host-resolved";
assert lib.hasInfix "nix-scout-settings" host.config.system.activationScripts.nix-scout-settings.text;
assert lib.hasInfix "fixture.nix" host.config.system.activationScripts.nix-scout-settings.text;
nixpkgs.legacyPackages.${system}.writeText "nix-scout-host-module-pass" "pass\n"
