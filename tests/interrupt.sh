#!/usr/bin/env bash
# Interrupt handling contracts for `nix-scout switch`.
set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/_lib.sh"

echo "== nix-scout switch interrupt handling =="
BIN="$REPO/bin/nix-scout"

if "$GREP" -q 'step_rc.*130\|step_rc.*-eq 130' "$BIN"; then
  pass "switch detects interrupt status 130 from child activity"
else
  fail "switch must detect interrupt status 130 from child activity"
fi

if "$GREP" -q 'module_rc.*130\|module_rc.*-eq 130' "$BIN"; then
  pass "switch stops module fan-out on interrupt"
else
  fail "switch must stop module fan-out on interrupt"
fi

if "$GREP" -qF 'switch_rc=$step_rc' "$BIN"; then
  pass "ordinary child failures still accumulate and continue"
else
  fail "ordinary child failures must still accumulate and continue"
fi

finish_suite
