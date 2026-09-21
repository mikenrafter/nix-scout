#!/usr/bin/env bash
# PATH shim so `nix scout …` works on CppNix.
#
# RegisterCommand plugins load *after* top-level subcommand resolution
# (RootArgs::initialFlagsProcessed), so `nix scout` fails even when the
# plugin-files shim is installed. This wrapper intercepts only the `scout`
# subcommand and execs nix-scout; everything else goes to the real nix.
set -euo pipefail

REAL_NIX="@real_nix@"
SCOUT="@nix_scout@"

if [[ "${1:-}" == "scout" ]]; then
  shift
  exec "$SCOUT" "$@"
fi

exec "$REAL_NIX" "$@"
