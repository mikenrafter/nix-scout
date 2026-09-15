# Adapters that turn existing NixOS and Home Manager modules into nix-scout
# facets. The source attrset carries the upstream modules and the fixed
# configuration from flake.nix. Runtime settings are merged last.

let
  sourceModules = source:
    source.modules or ([ source.module ]);

  settingsMeta = source: args:
    let configured = source.settings or { };
    in if builtins.isFunction configured then configured args
       else if configured ? settings then configured
       else { settings = configured; };

  sourceSettings = kind: source: args:
    ((settingsMeta source args).settings or { }).${kind} or { };

  mergeConfig = lib: source: overrides:
    lib.recursiveUpdate (source.config or { }) overrides;

  selectedNames = lib: discovered: selection:
    let
      include = selection.include or [ ];
      exclude = selection.exclude or [ ];
      chosen = if include == [ ] then discovered else include;
    in
    builtins.filter (name: !(builtins.elem name exclude)) chosen;

  evalNixos = source: overrides:
    let
      lib = source.nixpkgs.lib;
    in
    lib.nixosSystem {
      system = source.system;
      specialArgs = source.specialArgs or { };
      modules = sourceModules source ++ [ (mergeConfig lib source overrides) ];
    };

  evalNixosBase = source:
    source.nixpkgs.lib.nixosSystem {
      system = source.system;
      specialArgs = source.specialArgs or { };
      modules = source.baseModules or [ ];
    };

  nixosInspection = source: overrides:
    let
      lib = source.nixpkgs.lib;
      evaluated = evalNixos source overrides;
      base = evalNixosBase source;
      cfg = evaluated.config.systemd;
      baseCfg = base.config.systemd;
      groups = [ "services" "sockets" "timers" "targets" "paths" ];
      masks = lib.genAttrs groups (group:
        selectedNames lib
          (lib.subtractLists
            (builtins.attrNames (baseCfg.${group} or { }))
            (builtins.attrNames (cfg.${group} or { })))
          ((source.units or { }).${group} or { }));
      discoveredUnits = lib.subtractLists
        (builtins.attrNames base.config.systemd.units)
        (builtins.attrNames evaluated.config.systemd.units);
      units = selectedNames lib discoveredUnits (source.units or { });
    in
    {
      inherit evaluated masks units;
    };

  homeIdentity = source:
    let
      contextUser = (source.context or { }).user or { };
      configuredUser = source.user or { };
    in
    {
      name = contextUser.name or configuredUser.name or "nix-scout";
      homeDirectory =
        contextUser.homeDirectory or configuredUser.homeDirectory or "/home/nix-scout";
      stateVersion =
        contextUser.stateVersion
          or configuredUser.stateVersion
          or source.homeStateVersion
          or "26.05";
    };

  evalHome = source: overrides:
    let
      lib = source.nixpkgs.lib;
      pkgs = source.nixpkgs.legacyPackages.${source.system};
      user = homeIdentity source;
    in
    source.home-manager.lib.homeManagerConfiguration {
      inherit pkgs;
      extraSpecialArgs = source.extraSpecialArgs or { };
      modules = sourceModules source ++ [
        (mergeConfig lib source overrides)
        {
          home.username = lib.mkDefault user.name;
          home.homeDirectory = lib.mkDefault user.homeDirectory;
          home.stateVersion = lib.mkDefault user.stateVersion;
        }
      ];
    };

  evalHomeBase = source:
    let
      lib = source.nixpkgs.lib;
      pkgs = source.nixpkgs.legacyPackages.${source.system};
      user = homeIdentity source;
    in
    source.home-manager.lib.homeManagerConfiguration {
      inherit pkgs;
      extraSpecialArgs = source.extraSpecialArgs or { };
      modules = (source.baseModules or [ ]) ++ [
        {
          home.username = lib.mkDefault user.name;
          home.homeDirectory = lib.mkDefault user.homeDirectory;
          home.stateVersion = lib.mkDefault user.stateVersion;
        }
      ];
    };

  homeInspection = source: overrides:
    let
      lib = source.nixpkgs.lib;
      evaluated = evalHome source overrides;
      base = evalHomeBase source;
      entries = lib.filterAttrs (_: file: file.enable) evaluated.config.home.file;
      baseEntries = lib.filterAttrs (_: file: file.enable) base.config.home.file;
      introduced = lib.subtractLists
        (builtins.attrNames baseEntries)
        (builtins.attrNames entries);
      # Home Manager user units require daemon-reload and enablement semantics
      # that the plain home-files copier does not provide. Keep them in the
      # rebuild-only baseline until that activation path exists.
      discovered = builtins.filter
        (name:
          !(lib.hasPrefix ".config/systemd/user/" entries.${name}.target)
        )
        introduced;
      selected = selectedNames lib discovered (source.files or { });
      files = map (name: entries.${name}.target) selected;
    in
    {
      inherit evaluated files;
      masks = selected;
    };
in
{
  nixosModule = {
    inspect = source: overrides:
      let inspection = nixosInspection source overrides;
      in {
        inherit (inspection) units masks;
      };

    flakelet = source: { types, ... }: {
      nixScoutInspect =
        let inspection = nixosInspection source { };
        in {
          inherit (inspection) units masks;
        };

      options.nixos = {
        type = types.attrs;
        default = { };
        description = "NixOS module settings merged over the scout module defaults.";
      };
      options.homeManager = {
        type = types.attrs;
        default = { };
        description = "Home Manager settings reserved for the scout facet.";
      };

      impl = { options, name, ... }:
        let
          inspection = nixosInspection source (options.nixos or { });
          lib = source.nixpkgs.lib;
          supportedSuffixes = [ ".service" ".socket" ".timer" ".target" ".path" ];
          unsupported = builtins.filter
            (unit:
              !(builtins.any (suffix: lib.hasSuffix suffix unit) supportedSuffixes)
            )
            inspection.units;
          foreign = builtins.filter
            (unit:
              !(lib.hasPrefix "${name}." unit || lib.hasPrefix "${name}-" unit)
            )
            inspection.units;
        in
        if unsupported != [ ] then
          throw "nix-scout: flakelet adapter found unsupported units: ${lib.concatStringsSep ", " unsupported}"
        else if foreign != [ ] then
          throw "nix-scout: flakelet '${name}' cannot own units without its name prefix: ${lib.concatStringsSep ", " foreign}"
        else {
          units = lib.genAttrs inspection.units
            (unit:
              let rendered = inspection.evaluated.config.systemd.units.${unit}.unit;
              in source.nixpkgs.legacyPackages.${source.system}.runCommand
                "flakelet-unit-${unit}"
                { } ''
                cp ${rendered}/${unit} "$out"
              '');
        };
    };

    baseline = source: args@{ lib, ... }:
      let
        overrides = sourceSettings "nixos" source args;
        inspection = nixosInspection source overrides;
        maskGroup = group: names:
          lib.genAttrs names (_: { enable = lib.mkForce false; });
      in
      {
        imports = sourceModules source;
        config = lib.mkMerge [
          (mergeConfig lib source overrides)
          {
            systemd.services = maskGroup "services" inspection.masks.services;
            systemd.sockets = maskGroup "sockets" inspection.masks.sockets;
            systemd.timers = maskGroup "timers" inspection.masks.timers;
            systemd.targets = maskGroup "targets" inspection.masks.targets;
            systemd.paths = maskGroup "paths" inspection.masks.paths;
          }
        ];
      };
  };

  homeManagerModule = {
    inspect = source: overrides:
      let inspection = homeInspection source overrides;
      in {
        inherit (inspection) files masks;
      };

    scout = source:
      let
        lib = source.nixpkgs.lib;
        pkgs = source.nixpkgs.legacyPackages.${source.system};
        contextSettings = (source.context or { }).settings or null;
        staticSettings = source.settings or { };
        overrides =
          if contextSettings != null then
            (contextSettings.homeManager or { })
          else if builtins.isFunction staticSettings then
            throw "nix-scout: a Home Manager scout build cannot evaluate a host-dependent settings function; pass resolved settings through the scout context"
          else
            sourceSettings "homeManager" source { };
        inspection = homeInspection source overrides;
      in
      pkgs.runCommand "scout-home-manager-files"
        {
          passthru.nixScoutInspect = {
            inherit (inspection) files masks;
          };
        } ''
        mkdir -p "$out/home-files"
        cp -aL ${inspection.evaluated.activationPackage}/home-files/. "$out/home-files/"
      '';

    # `source.modules` is the full list for scout/inspect/masks.
    # `source.excludeFromHomeBaseline` lists module values to omit from
    # homeBaseline.imports only — for cases where a co-imported NixOS module
    # already injects the same HM module into home-manager.sharedModules
    # (niri-flake.nixosModules.niri → homeModules.config). Those modules are
    # still evaluated for harvest; re-importing them at rebuild time would
    # double-declare options.
    baseline = source: args@{ lib, ... }:
      let
        settingsArgs = args // {
          config = if args ? osConfig then args.osConfig else args.config;
        };
        overrides = sourceSettings "homeManager" source settingsArgs;
        inspection = homeInspection source overrides;
        excluded = source.excludeFromHomeBaseline or [ ];
      in
      {
        imports = builtins.filter
          (m: !(builtins.elem m excluded))
          (sourceModules source);
        config = lib.mkMerge [
          (mergeConfig lib source overrides)
          {
            home.file = lib.genAttrs inspection.masks
              (_: { enable = lib.mkForce false; });
          }
        ];
      };
  };
}
