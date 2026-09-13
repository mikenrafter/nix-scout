#!/usr/bin/env bash
# Copy a scout module flake to /tmp and stamp it with the parent flake.lock.
# A module's own committed flake.lock (see lib/update-module.sh) is itself
# just a copy of the parent's, kept in sync by `nix-scout update`/`switch`;
# the parent's lock is always the authoritative source — this re-stamps it
# fresh at materialize time regardless, so a build never depends on the
# module's committed copy having been synced recently.
# Prints the materialized directory path on stdout.
set -euo pipefail

MODULE_DIR="${1:?module directory required}"
NIX_SCOUT_PARENT="${NIX_SCOUT_PARENT:-}"

if [[ ! -f "$MODULE_DIR/flake.nix" ]]; then
  echo "materialize-module: missing flake.nix in $MODULE_DIR" >&2
  exit 1
fi

tmp="$(mktemp -d /tmp/nix-scout-XXXXXX)"
cp -a "$MODULE_DIR/." "$tmp/"
chmod -R u+w "$tmp"

parent_lock="${NIX_SCOUT_PARENT}/flake.lock"
if [[ -f "$parent_lock" ]]; then
  cp "$parent_lock" "$tmp/flake.lock"
  echo "nix-scout: materialize copied parent flake.lock into $tmp" >&2
elif [[ ! -f "$tmp/flake.lock" ]]; then
  (cd "$tmp" && (nix flake lock --no-write-lock-file 2>/dev/null || nix flake lock) >/dev/null)
fi

context_user="${NIX_SCOUT_USER:-${USER:-}}"
context_home="${NIX_SCOUT_HOME:-${HOME:-}}"
settings_dir="${NIX_SCOUT_SETTINGS_DIR:-/var/lib/nix-scout/settings}"
module_name="$(basename "$MODULE_DIR")"
resolved_settings="$settings_dir/$module_name.nix"

if [[ -f "$resolved_settings" ]]; then
  cp "$resolved_settings" "$tmp/scout-settings.nix"
fi

# JSON string syntax is also valid Nix string syntax. jq is already a
# nix-scout runtime dependency and avoids hand-written escaping for paths.
nix_string() {
  jq -Rn --arg value "$1" '$value'
}

{
  printf '%s\n' '{'
  printf '%s\n' '  version = 1;'
  printf '%s\n' '  mode = "switch";'
  printf '%s\n' '  systemRebuild = false;'
  if [[ -f "$tmp/scout-settings.nix" ]]; then
    printf '%s\n' '  settings = import ./scout-settings.nix;'
  else
    printf '%s\n' '  settings = { };'
  fi
  printf '%s\n' '  user = {'
  printf '    name = %s;\n' "$(nix_string "$context_user")"
  printf '    homeDirectory = %s;\n' "$(nix_string "$context_home")"
  printf '%s\n' '  };'
  printf '%s\n' '}'
} > "$tmp/scout-context.nix"

export NIX_SCOUT_MATERIALIZED="$tmp"
printf '%s\n' "$tmp"
