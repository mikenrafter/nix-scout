{
  outputs = inputs:
    let
      system = "x86_64-linux";
      settings = import ./settings.nix;

      nixosFixture = { config, lib, pkgs, ... }: {
        options.services.fixture.enable = lib.mkEnableOption "host adapter fixture";
        config = lib.mkIf config.services.fixture.enable {
          environment.etc."fixture-support".text = "baseline";
          systemd.services.fixture.serviceConfig = {
            Type = "oneshot";
            ExecStart = "${pkgs.coreutils}/bin/true";
          };
        };
      };

      homeFixture = { config, lib, ... }: {
        options.programs.fixture = {
          enable = lib.mkEnableOption "home adapter fixture";
          message = lib.mkOption {
            type = lib.types.str;
            default = "default";
          };
        };
        config = lib.mkIf config.programs.fixture.enable {
          home.sessionVariables.NIX_SCOUT_ADAPTER_HOST = "present";
          home.file.".config/fixture/message".text = config.programs.fixture.message;
        };
      };

      nixosSource = {
        inherit system settings;
        nixpkgs = inputs.nixpkgs;
        modules = [ nixosFixture ];
        config.services.fixture.enable = true;
      };

      context = inputs.nix-scout.lib.readContext ./. inputs;
      homeSource = {
        inherit context settings system;
        home-manager = inputs.home-manager;
        nixpkgs = inputs.nixpkgs;
        modules = [ homeFixture ];
        homeStateVersion = "26.05";
        config.programs.fixture.enable = true;
      };
    in
    {
      packages.${system}.scout =
        inputs.nix-scout.lib.homeManagerModule.scout homeSource;
      homeBaseline =
        inputs.nix-scout.lib.homeManagerModule.baseline homeSource;
      baseline =
        inputs.nix-scout.lib.nixosModule.baseline nixosSource;
      flakelets.default =
        inputs.nix-scout.lib.nixosModule.flakelet nixosSource;
    };
}
