#!/usr/bin/env bash
set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/_lib.sh"

require_nix
echo "== mkScoutModule optional pkgs =="

run_capture env NIX_SCOUT_ROOT="$NIX_SCOUT_ROOT" \
  "$NIX" eval --impure --raw --no-write-lock-file \
  --expr 'let
    root = builtins.getFlake (toString ./.);
  in import ./tests/mk-scout-module.nix {
    nixpkgs = root.inputs.nixpkgs;
    nixScout = root;
  }'

if [[ "$CAPTURED_RC" -eq 0 && "$CAPTURED_OUT" == "pass" ]]; then
  pass "provided and fallback pkgs paths evaluate"
else
  fail "mkScoutModule optional pkgs test failed: $(printf %q "$CAPTURED_ERR$CAPTURED_OUT")"
fi

finish_suite
