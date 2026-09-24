# Consuming NixOS and Home Manager modules

## Goal

A scout module may reuse an upstream NixOS module or Home Manager module. Nix-scout derives the hot-swappable facet and applies the rest during a normal rebuild.

Existing hand-written facets remain valid. The adapters fit into the current `flake.nix` facet split and use the existing `settings.nix` file for host-derived values.

## Authoring model

The module author declares a shared source inside `flake.nix`:

```nix
outputs = { nix-scout, paseo, ... }@inputs:
let
  system = "x86_64-linux";

  source = {
    inherit (inputs) nixpkgs;
    inherit system;
    modules = [ paseo.nixosModules.default ];
    settings = import ./settings.nix;
    config.services.paseo = {
      enable = true;
      package = paseo.packages.${system}.default;
    };
  };
in
nix-scout.lib.mkScoutModule ./. inputs {
  baseline = _: { baseline = nix-scout.lib.nixosModule.baseline source; };
  flakelet = _: { flakelets.default = nix-scout.lib.nixosModule.flakelet source; };
};
```

A Home Manager source uses the same pattern:

```nix
context = nix-scout.lib.readContext ./. inputs;

source = {
  inherit home-manager nixpkgs system;
  modules = [ app.homeModules.default ];
  settings = import ./settings.nix;
  inherit context;
  homeStateVersion = "26.05";
  config.programs.app.enable = true;
};

packages.${system}.scout =
  nix-scout.lib.homeManagerModule.scout source;

homeBaseline =
  nix-scout.lib.homeManagerModule.baseline source;
```

Authors may compose generated baselines with local modules:

```nix
baseline.imports = [
  (nix-scout.lib.nixosModule.baseline source)
  ./baseline.nix
];
```

## Settings

`settings.nix` stays a Nix file and remains the configuration file consumed by flakelet. It supplies host-dependent overrides for either adapter:

```nix
{ config, ... }:
{
  enable = config.v0id.paseo.enable;
  output = "flakelets.default";

  settings = {
    nixos.services.paseo = {
      port = config.v0id.paseo.port;
      listenAddress = config.v0id.paseo.listenAddress;
      passwordFile = config.sops.secrets.paseo_password.path;
    };

    homeManager.programs.paseo = {
      enable = true;
      dataDir = config.v0id.paseo.dataDir;
    };
  };

  autoUpdate = {
    enable = true;
    interval = "hourly";
  };
}
```

The adapters merge configuration in this order:

1. Upstream module defaults.
2. The `config` declared in `flake.nix`.
3. The matching override from `settings.nix`.

`settings.nix` wins. Secret contents must not appear in settings because flakelet stores the evaluated settings. Secret file paths are safe and match flakelet's existing convention.

## Transformations

### NixOS module to flakelet

Evaluate the upstream module in an isolated NixOS configuration. Compare it with a base evaluation to discover the units introduced by the source. Take the already-rendered derivations from `config.systemd.units.<name>.unit` and return them through flakelet's raw `units` interface.

Support services, sockets, timers, targets, and paths. Reject unsupported unit kinds and names that violate flakelet's ownership rules. Allow explicit `include` and `exclude` lists when discovery needs help.

### Home Manager module to scout files

Evaluate a Home Manager generation with the real user name and home directory. Expose the generation's `home-files` tree as `packages.<system>.scout/home-files`. This covers `home.file`, XDG file options, generated text, and recursive sources without reimplementing Home Manager's file logic.

Home Manager activation entries remain rebuild-only. User systemd units need reload and enable handling before they can be switched safely.

### Rebuild-only masks

Import the original module during a normal rebuild, but disable only the entries extracted from that source:

- Set extracted NixOS unit entries to `enable = lib.mkForce false`.
- Set extracted `home.file` entries to `enable = lib.mkForce false`.

Packages, users, groups, firewall rules, environment configuration, activation entries, and other support configuration remain active. The masks must never affect definitions contributed by unrelated host modules.

### Dual NixOS + Home Manager entrypoints

Some upstream flakes expose both a NixOS module and a Home Manager module that
each import the same options file (niri-flake: `nixosModules.niri` injects
`homeModules.config` into `home-manager.sharedModules`; `homeModules.niri`
also imports it). Listing both in `source.modules` is correct for
scout/inspect, but `homeBaseline` must not re-import the wrapper or options
are declared twice.

Set `source.homeBaselineModules` to the modules that should be imported at
rebuild time (typically everything in `modules` except the wrapper the NixOS
side already covers). Harvest and masks still use the full `modules` list.
Do not try to exclude by module reference — Nix function equality is always
false, so `builtins.elem` cannot filter lambdas.

## Scout context

`scout-context.nix` is a temporary sidecar created in the materialized module directory by `nix-scout switch`. Rebuild evaluation passes the same versioned context directly to the scout module's `outputs` function with `systemRebuild = true` and the host-resolved settings. It does not create the file. Flakelet evaluates the live module directory and does not use this file.

Expand the sidecar to a versioned context:

```nix
{
  version = 1;
  mode = "switch";
  systemRebuild = false;
  settings = import ./scout-settings.nix;
  user = {
    name = "v0id";
    homeDirectory = "/home/v0id";
  };
}
```

This gives a Home Manager-backed switch build the invoking user's real identity. `settings.nix` remains the authored settings file and flakelet continues to evaluate it directly. During a rebuild, nix-scout evaluates that file against the host configuration. It passes the resulting `settings` attrset to the rebuild evaluation and saves the attrset as Nix for later switches. The switch materializer copies that resolved Nix expression next to `scout-context.nix`, which imports it as `context.settings`. There is no JSON settings format for the adapters.

## Inspection

Add `nix-scout inspect <name>`. It evaluates a module without applying it and reports:

- resolved adapter settings,
- discovered flakelet units,
- discovered home files,
- generated baseline masks,
- local baseline modules,
- unsupported output and ownership conflicts.

`nix-scout list` keeps its short facet summary. `inspect` owns the detailed explanation.

## Delivery order

1. Add evaluation tests for NixOS unit extraction, settings overrides, and baseline masking.
2. Implement the NixOS adapter.
3. Add evaluation tests for Home Manager file extraction, settings overrides, real user context, and baseline masking.
4. Implement the Home Manager adapter and per-user rebuild evaluation.
5. Extend `scout-context.nix` with version, mode, and user identity.
6. Add `nix-scout inspect` and conflict diagnostics.
7. Update `nix-scout new`, the README, the manual, and completions.
8. Test synthetic modules first, then representative upstream NixOS and Home Manager modules.
