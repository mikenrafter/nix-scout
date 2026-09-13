#!/usr/bin/env bash
set -euo pipefail

# shellcheck source=_lib.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/_lib.sh"

require_nix

echo "== module adapters =="

run_capture env NIX_SCOUT_ROOT="$NIX_SCOUT_ROOT" \
  "$NIX" build --no-link --print-out-paths --no-write-lock-file \
  --impure --expr \
  'let
     root = builtins.getEnv "NIX_SCOUT_ROOT";
     f = builtins.getFlake root;
   in import (root + "/tests/module-adapters.nix") {
     nixpkgs = f.inputs.nixpkgs;
     home-manager = f.inputs.home-manager;
     nixScout = f;
   }'

if [[ "$CAPTURED_RC" -eq 0 ]]; then
  pass "NixOS and Home Manager adapters evaluate"
else
  fail "module adapter evaluation failed: $(printf %q "$CAPTURED_ERR")"
fi

finish_suite
