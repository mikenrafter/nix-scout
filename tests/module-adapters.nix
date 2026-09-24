{ nixpkgs, home-manager, nixScout }:

let
  system = "x86_64-linux";
  lib = nixpkgs.lib;
  pkgs = nixpkgs.legacyPackages.${system};
  adapters = nixScout.lib;

  nixosFixture = { config, lib, pkgs, ... }: {
    options.services.adapter-fixture = {
      enable = lib.mkEnableOption "adapter fixture";
      port = lib.mkOption {
        type = lib.types.port;
        default = 4100;
      };
    };

    config = lib.mkIf config.services.adapter-fixture.enable {
      users.groups.adapter-fixture = { };
      environment.etc."adapter-fixture-port".text =
        toString config.services.adapter-fixture.port;
      systemd.services.adapter-fixture = {
        description = "nix-scout adapter fixture";
        wantedBy = [ "multi-user.target" ];
        serviceConfig = {
          Type = "oneshot";
          ExecStart = "${pkgs.coreutils}/bin/echo ${toString config.services.adapter-fixture.port}";
        };
      };
    };
  };

  nixosSource = {
    inherit nixpkgs system;
    modules = [ nixosFixture ];
    config.services.adapter-fixture.enable = true;
    settings = { ... }: {
      settings.nixos.services.adapter-fixture.port = 4200;
    };
  };

  nixosInfo = adapters.nixosModule.inspect nixosSource {
    services.adapter-fixture.port = 4200;
  };

  nixosBaseline = lib.nixosSystem {
    inherit system;
    modules = [
      (adapters.nixosModule.baseline nixosSource)
    ];
  };

  fakeTypes = {
    attrs = { name = "attrs"; };
  };
  flakeletDefinition = adapters.nixosModule.flakelet nixosSource { types = fakeTypes; };
  flakeletResult = flakeletDefinition.impl {
    options.nixos.services.adapter-fixture.port = 4200;
    inherit pkgs;
    name = "adapter-fixture";
  };

  foreignUnitSource = nixosSource // {
    config = {
      services.adapter-fixture.enable = true;
      systemd.services.foreign-unit.serviceConfig.ExecStart =
        "${pkgs.coreutils}/bin/true";
    };
  };
  foreignDefinition = adapters.nixosModule.flakelet foreignUnitSource {
    types = fakeTypes;
  };
  foreignResult = builtins.tryEval (builtins.attrNames
    (foreignDefinition.impl {
      options.nixos = { };
      inherit pkgs;
      name = "adapter-fixture";
    }).units);

  homeFixture = { config, lib, ... }: {
    options.programs.adapter-home = {
      enable = lib.mkEnableOption "adapter home fixture";
      message = lib.mkOption {
        type = lib.types.str;
        default = "default";
      };
    };

    config = lib.mkIf config.programs.adapter-home.enable {
      home.sessionVariables.ADAPTER_HOME = "kept-in-baseline";
      home.file.".config/adapter/message".text =
        config.programs.adapter-home.message;
      systemd.user.services.adapter-agent = {
        Unit.Description = "adapter agent";
        Service.ExecStart = "${pkgs.coreutils}/bin/true";
      };
    };
  };

  homeSource = {
    inherit home-manager nixpkgs system;
    modules = [ homeFixture ];
    config.programs.adapter-home.enable = true;
    context = {
      user = {
        name = "fixture";
        homeDirectory = "/home/fixture";
      };
      settings.homeManager.programs.adapter-home.message = "from-settings";
    };
    homeStateVersion = "26.05";
    settings = { ... }: {
      settings.homeManager.programs.adapter-home.message = "from-baseline-settings";
    };
  };

  homeInfo = adapters.homeManagerModule.inspect homeSource { };
  homeBaseline = home-manager.lib.homeManagerConfiguration {
    inherit pkgs;
    modules = [
      (adapters.homeManagerModule.baseline homeSource)
      {
        home.username = "fixture";
        home.homeDirectory = "/home/fixture";
        home.stateVersion = "26.05";
      }
    ];
  };
  homeScout = adapters.homeManagerModule.scout homeSource;

  # Dual-entrypoint coexistence: sharedConfig is what a NixOS module would
  # inject via sharedModules; wrapper imports it (like homeModules.niri).
  # homeBaselineModules lists only the consumer — scout/inspect still use
  # the full modules list (wrapper + consumer) for harvest and masks.
  sharedConfigModule = { lib, ... }: {
    options.programs.dual.message = lib.mkOption {
      type = lib.types.str;
      default = "shared";
    };
    config.home.file.".config/dual/from-shared".text = "shared";
  };
  wrapperModule = { lib, ... }: {
    imports = [ sharedConfigModule ];
    options.programs.dual.enable = lib.mkEnableOption "dual";
    config.home.file.".config/dual/from-wrapper".text = "wrapper";
  };
  consumerModule = { lib, ... }: {
    config.home.file.".config/dual/from-consumer".text = "consumer";
  };
  dualSource = {
    inherit home-manager nixpkgs system;
    modules = [ wrapperModule consumerModule ];
    homeBaselineModules = [ consumerModule ];
    homeStateVersion = "26.05";
    context.user = {
      name = "fixture";
      homeDirectory = "/home/fixture";
    };
  };
  dualInfo = adapters.homeManagerModule.inspect dualSource { };
  # Rebuild path: sharedConfig already present (NixOS injection), plus
  # homeBaseline that imports only consumerModule.
  dualBaseline = home-manager.lib.homeManagerConfiguration {
    inherit pkgs;
    modules = [
      sharedConfigModule
      (adapters.homeManagerModule.baseline dualSource)
      {
        home.username = "fixture";
        home.homeDirectory = "/home/fixture";
        home.stateVersion = "26.05";
      }
    ];
  };
  # Without homeBaselineModules, baseline re-imports the wrapper and
  # double-declares sharedConfig's options against the NixOS injection.
  # The duplicate declaration only throws once that option is read.
  dualWithoutSplit = builtins.tryEval (
    (home-manager.lib.homeManagerConfiguration {
      inherit pkgs;
      modules = [
        sharedConfigModule
        (adapters.homeManagerModule.baseline (builtins.removeAttrs dualSource [ "homeBaselineModules" ]))
        {
          home.username = "fixture";
          home.homeDirectory = "/home/fixture";
          home.stateVersion = "26.05";
        }
      ];
    }).config.programs.dual.message
  );
in
assert builtins.elem "adapter-fixture.service" nixosInfo.units;
assert builtins.elem "adapter-fixture" nixosInfo.masks.services;
assert flakeletDefinition.nixScoutInspect.units == nixosInfo.units;
assert nixosBaseline.config.systemd.services.adapter-fixture.enable == false;
assert nixosBaseline.config.users.groups ? adapter-fixture;
assert nixosBaseline.config.environment.etc."adapter-fixture-port".text == "4200";
assert flakeletResult.units ? "adapter-fixture.service";
assert lib.hasInfix "4200"
  (builtins.readFile flakeletResult.units."adapter-fixture.service");
assert foreignResult.success == false;
assert builtins.elem ".config/adapter/message" homeInfo.files;
assert homeInfo.masks == [ ".config/adapter/message" ];
assert homeBaseline.config.home.sessionVariables.ADAPTER_HOME == "kept-in-baseline";
assert homeBaseline.config.home.file.".config/adapter/message".enable == false;
assert builtins.any
  (file: file.target == ".config/systemd/user/adapter-agent.service" && file.enable)
  (builtins.attrValues homeBaseline.config.home.file);
assert builtins.readFile "${homeScout}/home-files/.config/adapter/message" == "from-settings";
assert homeScout.nixScoutInspect.masks == [ ".config/adapter/message" ];
assert builtins.elem ".config/dual/from-shared" dualInfo.files;
assert builtins.elem ".config/dual/from-wrapper" dualInfo.files;
assert builtins.elem ".config/dual/from-consumer" dualInfo.files;
assert dualBaseline.config.home.file.".config/dual/from-shared".enable == false;
assert dualBaseline.config.home.file.".config/dual/from-wrapper".enable == false;
assert dualBaseline.config.home.file.".config/dual/from-consumer".enable == false;
assert dualWithoutSplit.success == false;
pkgs.writeText "nix-scout-module-adapters-pass" "pass\n"
