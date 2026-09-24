# nix-scout

Frontrunner profile + scout module switcher for NixOS flakes.

`nix-scout` lets optional features/tools live as small, self-contained
flakes ("scout modules") dropped into a directory inside your NixOS
config repo (the "host flake"), and lets you build and apply any one of
them on demand — install a package into a dedicated profile, drop files
into `$HOME`, or (de)register a systemd service — without running a full
`nixos-rebuild`.

## Concepts

- **Host flake** — your normal NixOS config repo. It wires in
  `nix-scout`'s `nixosModule` and points it at a modules directory.
- **Scout module** — a directory under that modules directory containing
  its own `flake.nix` (`<modules-dir>/<name>/flake.nix`). Modules carry no
  committed `flake.lock` — the host flake's lock is stamped onto them at
  switch time, so a module's inputs resolve to the same revisions your
  host already uses.
- **Facets** — what a module's `flake.nix` can export, independently:
  - `scout` — `packages.<system>.scout`, installed into a dedicated
    per-user Nix profile (`bin/` subdirectory).
  - `home` — also part of `packages.<system>.scout`, via a `home-files/`
    subdirectory copied verbatim into `$HOME`. Applied both by
    `nix-scout switch <name>` and, automatically for every normal user, by
    a real `nixos-rebuild` — no separate switch needed to get a module's
    config onto disk once its `home-files/` is built. Files that later
    vanish from the config are handled per the removal policies described
    in [Home-file removal policies](#home-file-removal-policies).
  - `flakelet` — `flakelets.<attr>`, a [flakelet](https://github.com/Mic92/flakelet)
    systemd unit, applied on `nixos-rebuild` and refreshed on switch.
  - `baseline` — a real NixOS module (function or attrset), imported directly
    into the host's module list at `nixos-rebuild` eval time. Because it's a
    genuine module import rather than something routed through a switch
    script, it can set **any** system-wide option — `nix.settings`, `boot.*`,
    arbitrary `services.*`, and so on — and it can read the host's own
    `config`/`lib` like any ordinary module. `nix-scout switch` never builds
    or applies `baseline` at all; it only takes effect on the next rebuild.

Every scout module's `flake.nix` declares `inputs.nix-scout` and composes
facets through `inputs.nix-scout.lib.mkScoutModule`:

```nix
{
  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";
  inputs.nix-scout.url = "github:mikenrafter/nix-scout";
  inputs.nix-scout.inputs.nixpkgs.follows = "nixpkgs";

  outputs = { nixpkgs, ... }@inputs:
  inputs.nix-scout.lib.mkScoutModule ./. inputs {
    # scout
    scout = { pkgs, system, ... }: { packages.${system}.scout = ...; };
    # home
    # baseline
    baseline = { ... }: { baseline = import ./baseline.nix; };
    # flakelet
    flakelet = { pkgs, lib, ... }: { flakelets.default = ...; };
  };
}
```

`mkScoutModule` gates `scout`/`home`/`baseline` using `scout-context.nix`
(switch), the host rebuild prebuild (`systemRebuild = true`), or
`scoutContext` passed from the NixOS module — not whether `nix-scout`
appears in the flake input attrset. Flakelet evaluation via
`builtins.getFlake` only forces the `flakelet` facet (lazy attr selection).

## Install

Add it as a flake input and wire in the NixOS module from your host flake:

```nix
inputs.nix-scout.url = "github:mikenrafter/nix-scout";

# In your NixOS system config:
imports = [
  (inputs.nix-scout.nixosModule
    (toString ./.)          # parent: live path to your host flake root
    "scout-modules"         # modulesRel: dir under parent with <name>/flake.nix drop-ins
    inputs)                 # hostInputs: your flake's own resolved `inputs`
];
```

On activation this writes `/var/lib/nix-scout/paths` (`NIX_SCOUT_PARENT`,
`NIX_SCOUT_MODULES`), which the `nix-scout` CLI reads at runtime — without
it, every subcommand exits with a pointer back to this step. It also wires
`environment.systemPackages` to prebuild any module exporting `scout`,
copies every module's `home-files/` into each normal user's `$HOME` (run as
that user via `runuser`, not root — a module missing this step is why a
tool can be on `$PATH` after a rebuild but still fail with "missing
config"), registers `flakelet` facets into `services.flakelets`, and (via a
forced Home Manager shared module) puts the scout profile's `bin/`,
`share`, and man path ahead of the stale system copies for fish/bash/zsh.

## Day-to-day usage

```bash
nix-scout list                     # modules + detected facets
nix-scout new my-tool scout home   # scaffold scout-modules/my-tool/flake.nix (+ stub impls)
nix-scout switch my-tool           # materialize, build .#scout, install/apply it
nix-scout switch my-tool --show-trace   # NIX-FLAGS forward straight to `nix build`
nix-scout switch /nix/store/...    # or ref#attr — install a path directly, no module needed
nix-scout status                   # active profile, gc-roots, flakelet status
nix-scout clear                    # uninstall everything from the scout profile
nix-scout doctor                   # check + repair flakelet path-access issues
nix-scout completions fish         # also: bash, zsh
```

`switch` fans out per facet and no-ops on whichever one a module doesn't
export: package facet gets `nix build .#scout`, gc-root pinned, `bin/`
installed into the profile via `nix-env`, `home-files/` copied into
`$HOME`; flakelet facet runs `sudo flakelet update <name>` against the
entry already registered in `/etc/flakelet.json` by a prior
`nixos-rebuild` (if it's not there yet, rebuild once, then switch again).

`sudo nix-scout ...` is supported — it resolves the real invoking user's
`$HOME`/profile paths from `SUDO_USER`/`/etc/passwd` rather than acting as
root. Running it directly as root with no `SUDO_USER` is rejected.

### Authoring a module

`nix-scout new` scaffolds the facet-separation boilerplate above with stub
implementations for whichever facets you ask for:

```bash
nix-scout new my-tool scout            # packages.${system}.scout (buildEnv, bin/ only)
nix-scout new my-tool scout home       # same, plus a home-files/ subdirectory
nix-scout new my-tool flakelet         # flakelets.default + settings.nix stub
nix-scout new my-tool baseline         # a NixOS-module stub, imported on rebuild only
```

It also drops a placeholder `flake.lock` (nixpkgs `narHash` of zeros;
other locked identity fields are the literal sentinel string
`nix-scout_not-real-lockfile`) so the module evaluates standalone before
its first real switch stamps the host's actual lock over it. **Never run
`nix flake lock` inside a scout module directory** — that sentinel is
intentional, not a stale lock to fix.

A `flakelet` facet also needs `settings.nix` next to `flake.nix`, returning
`{ enable, output ? "flakelets.default", settings, autoUpdate ? {...} }`
— `nix-scout new ... flakelet` writes a working stub for this too. Missing
`settings.nix` on a module that exports `flakelets` is a hard eval error
at rebuild time.

Modules can tell rebuild-time prebuilds apart from `nix-scout switch` via
`systemRebuild` (`true` during a NixOS rebuild's prebuild pass, `false`
during `switch`, which writes a `scout-context.nix` next to the
materialized flake) — see `lib/scout-module.nix`'s `readSystemRebuild` for
the read pattern. Useful for shipping a lightweight stub in
`environment.systemPackages` while reserving a heavier payload for
explicit `switch`.

### Adapting existing modules

Nix-scout can derive facets from existing NixOS and Home Manager modules.
Keep the source declaration in the normal facet-separated `flake.nix`:

```nix
outputs = { nixpkgs, nix-scout, paseo, ... }@inputs:
let
  system = "x86_64-linux";
  lib = nixpkgs.lib;
  source = {
    inherit nixpkgs system;
    modules = [ paseo.nixosModules.default ];
    settings = import ./settings.nix;
    config.services.paseo.enable = true;
  };
in
inputs.nix-scout.lib.mkScoutModule ./. inputs {
  baseline = nix-scout.lib.nixosModule.baseline source;
  flakelet = { ... }: {
    flakelets.default = nix-scout.lib.nixosModule.flakelet source;
  };
};
```

The flakelet adapter evaluates the NixOS module and extracts its rendered
service, socket, timer, target, and path unit files. The generated baseline
imports the original module but disables the extracted units. Users, groups,
firewall rules, files under `/etc`, and other supporting configuration remain
part of the normal rebuild.

Put host-derived overrides under `settings.nixos`. They use the original
NixOS option paths and override the fixed `config` from `flake.nix`:

```nix
{ config, ... }: {
  enable = config.v0id.paseo.enable;
  settings.nixos.services.paseo = {
    port = config.v0id.paseo.port;
    passwordFile = config.sops.secrets.paseo_password.path;
  };
  autoUpdate = { enable = true; interval = "hourly"; };
}
```

For Home Manager, pass the switch context so the standalone build uses the
invoking user's name and home directory:

```nix
let
  context = nix-scout.lib.readContext ./. inputs;
  source = {
    inherit nixpkgs system context;
    home-manager = inputs.home-manager;
    modules = [ app.homeModules.default ];
    settings = import ./settings.nix;
    homeStateVersion = "26.05";
    config.programs.app.enable = true;
  };
in {
  packages.${system}.scout =
    nix-scout.lib.homeManagerModule.scout source;
  homeBaseline =
    nix-scout.lib.homeManagerModule.baseline source;
}
```

The scout package contains the files generated by Home Manager. The
`homeBaseline` keeps the module's remaining configuration and disables only
those extracted files. User systemd units remain rebuild-only because a plain
home-file copy cannot safely reproduce Home Manager's reload and enablement
steps.

When a co-imported NixOS module already injects the same Home Manager module
into `home-manager.sharedModules` (niri-flake's `nixosModules.niri` injects
`homeModules.config`), set `homeBaselineModules` to the subset that should
actually be imported at rebuild time. Scout/inspect still evaluate the full
`modules` list for harvest and masks. (An exclude-by-reference list cannot
work: Home Manager modules are lambdas, and Nix function equality is always
false.)

```nix
source = {
  modules = [
    niri-flake.homeModules.niri
    ./niri-config.nix
  ];
  # homeModules.niri imports homeModules.config; nixosModules.niri already
  # injects that same module via sharedModules — import only the rest.
  homeBaselineModules = [ ./niri-config.nix ];
  # ...
};
homeBaseline = nix-scout.lib.homeManagerModule.baseline source;
```

`settings.nix` remains a Nix file and is still consumed directly by flakelet.
During a rebuild, nix-scout resolves the `settings` attrset against the host
configuration. It passes that attrset to scout package evaluation and writes it
as Nix under `/var/lib/nix-scout/settings/`. A later `nix-scout switch` copies
the Nix expression into the temporary module and exposes it through
`scout-context.nix`. This lets `settings.homeManager` override a standalone
Home Manager-backed scout build.

Use `nix-scout inspect <name>` to evaluate a module and report its facets,
adapter type, generated unit or file inventory, masks, settings source, and
resolved flakelet setting paths.

The `scout`, `home`, and `flakelet` facets cannot set system-wide NixOS
options — that's what your core host config is for, or, from inside a scout
module, the `baseline` facet: `baseline = { config, lib, ... }: { ... };`
is imported directly into the host's module list on `nixos-rebuild` and can
set anything an ordinary NixOS module could. It is never touched by
`nix-scout switch` — only a rebuild picks it up.

### Home-file removal policies

Files nix-scout copies into `$HOME` are mutable regular copies (so you can
edit them), which means a file can outlive its config entry — dropped from a
module's `home-files/` tree, or from your Home Manager config — and you may
have edited it since it was applied. Both home-files activators therefore
track what they applied and handle vanished files per a per-file policy:

| policy | rebuild activation | `nix-scout switch` (CLI) |
|---|---|---|
| `remove` (default) | deleted | reported: "a rebuild would delete it" |
| `keep` | left in place, silently | reported |
| `keep-if-modified` | deleted only if it still matches the baseline nix-scout last wrote; kept (and reported) if you edited it | reported |
| `inform` | left in place + "no longer managed" notice | same notice |

Two hard rules:

- **The nix-scout CLI never deletes.** Only the NixOS module's activation
  scripts do. A `switch` run reports every vanished file with exactly what
  the next rebuild would do under its policy — including the deletions it is
  skipping.
- **Baselines are per file, recorded when nix-scout writes it.** A
  `keep-if-modified` file only survives deletion while it differs from the
  baseline the activator last set; revert your edits and the next rebuild
  cleans it up. Files applied before this existed have no baseline on record
  and are treated as modified (kept).

Scout modules declare non-default policies with a `home-manage.json` sibling
of `home-files/` in the package output — a JSON object mapping
`home-files/`-relative paths to a policy:

```nix
packages.${system}.scout = pkgs.runCommand "scout-${NAME}-home" { } ''
  mkdir -p $out/home-files/.config/${NAME}
  echo '{}' > $out/home-files/.config/${NAME}/config.json
  cp ${pkgs.writeText "${NAME}-home-manage.json" (builtins.toJSON {
       ".config/${NAME}/config.json" = "keep-if-modified";
     })} $out/home-manage.json
'';
```

For Home Manager files (`home.file` entries copied by nix-scout's forced
activator), set the per-user option the module defines:

```nix
nix-scout.homeFilePolicies = {
  ".config/DankMaterialShell/settings.json" = "keep-if-modified";
  ".config/old-tool/legacy.conf" = "inform";
};
```

Tracking records live in `~/.local/state/nix-scout/`: the per-module
manifests under `home-files/` (scout modules) and the per-run diff logs under
`diffs/`. One known constraint: the rebuild activation pins the state dir to
`$HOME/.local/state` (activation runs as the user via `runuser` and cannot
see a custom `XDG_STATE_HOME` from your interactive environment).

## Troubleshooting

`nix-scout doctor` checks (and where possible repairs) the usual failure
mode: flakelet evaluates modules as a dedicated `eval_user` via
setuid/setgid *without* `initgroups`, so supplementary group membership
(e.g. being in `users`) doesn't help it reach your modules directory. It
checks primary-gid-only path access, grants `o+x`/`o+rx` where needed,
confirms `/var/lib/flakelet` is readable, and reports any flakelet
services in an error or held state via `flakelet status --json`.

## Testing

Static, grep-only contract suites need no build and run in CI via
`checks.${system}.static-contracts`:

```
nix flake check
```

covers `module-mode`, `path-session`, `activation-clear`, `flakelet`,
`new-module`, `baseline`, and `completions`. Suites that need the built binary
(`cli`, `hm-activate-files`, `home-files-cleanup`, `materialize`,
`profile-gcroots`) are run manually:

```
nix develop
ns-test              # all suites in tests/ (or: ns-test cli, ns-test materialize, ...)
tests/run.sh          # same, outside the devshell
```

`ns-sandbox` (also from the devshell) runs a command inside a bubblewrap
sandbox with tmpfs standing in for the per-user Nix profile and gc-roots
directories, so you can exercise `switch`/`clear` without touching your
real system profile:

```
ns-sandbox nix-scout switch my-tool
```

## Reference

- `nix-scout --help` / `man nix-scout` (`share/man/man1/nix-scout.1`) — full
  command reference, environment variables, files written, exit codes.
- `bin/nix-scout` — the CLI itself; `usage()` is the source of truth if
  this README and the man page ever drift.
- `lib/*.sh` — one script per concern (`materialize-module.sh`,
  `apply-hm.sh`, `apply-env.sh`, `apply-flakelet.sh`, `new-module.sh`,
  `flakelet-access.sh`, `hm-activate-files.sh`).
- `nixos-module.nix` — the actual NixOS module logic behind
  `self.nixosModule`.

Version 0.8.0. Bash implementation, no compiled binary. Depends on
`nixpkgs`, `nixpkgs-unstable`, `home-manager`, and `github:Mic92/flakelet`.
MIT licensed.
