#!/usr/bin/env bash
# NixOS activation: system.activationScripts.nix-scout-clear clears profile +
# gc-roots immediately on switch, or once at first boot for a new generation.
#
# Run from repo root:
#   modules/nix-scout/tests/activation-clear.sh
set -euo pipefail

# shellcheck source=_lib.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/_lib.sh"

echo "== NixOS activation clear =="

# Resolve the binary so NIX_SCOUT_ROOT is set.
BIN=""
if BIN="$(resolve_nix_scout)"; then
  pass "resolved nix-scout at $BIN (NIX_SCOUT_ROOT=$NIX_SCOUT_ROOT)"
else
  fail "nix-scout binary not resolved — NIX_SCOUT_ROOT unknown; activation tests limited"
fi

NS_MODULE="${NIX_SCOUT_ROOT:-}/nixos-module.nix"
if [[ -f "$NS_MODULE" ]]; then
  pass "nixos-module.nix found at $NS_MODULE"

  if "$GREP" -qE 'activationScripts\.nix-scout-config|/var/lib/nix-scout/paths' "$NS_MODULE"; then
    pass "system.activationScripts.nix-scout-config writes /var/lib/nix-scout/paths"
  else
    fail "activation must write /var/lib/nix-scout/paths ($NS_MODULE)"
  fi

  if "$GREP" -qE 'activationScripts\.nix-scout-clear|system\.activationScripts\.nix-scout' "$NS_MODULE"; then
    pass "system.activationScripts.nix-scout-clear (or equivalent) defined"
  else
    fail "activation script not found in $NS_MODULE (want system.activationScripts.nix-scout-clear)"
  fi

  CLEAR_BLOCK="$(awk '/system\.activationScripts\.nix-scout-clear = \{/{f=1} f{print} f && /^  \};/{exit}' "$NS_MODULE")"
  if [[ -z "$CLEAR_BLOCK" ]]; then
    fail "could not isolate the nix-scout-clear activationScripts block ($NS_MODULE)"
  elif printf '%s' "$CLEAR_BLOCK" | "$GREP" -q 'NIXOS_ACTION.*boot' \
    && printf '%s' "$CLEAR_BLOCK" | "$GREP" -q 'clear_marker' \
    && printf '%s' "$CLEAR_BLOCK" | "$GREP" -q 'systemConfig'; then
    pass "activation clear is guarded by boot action and generation marker"
  else
    fail "activation clear must defer boot cleanup and record the generation ($NS_MODULE)"
  fi

  if "$GREP" -qE 'nix-env|NIX_SCOUT_PROFILE|profiles/per-user/.*/nix-scout' "$NS_MODULE" \
    && "$GREP" -qE 'gcroots|NIX_SCOUT_GCROOTS' "$NS_MODULE"; then
    pass "activation clear mentions profile + gc-roots cleanup"
  else
    fail "activation clear does not reset profile + gc-roots ($NS_MODULE)"
  fi

  # Clear script uninstalls/removes profile — must use --uninstall or rm -f.
  if "$GREP" -qE 'uninstall|rm -f' "$NS_MODULE"; then
    pass "activation clear uses --uninstall or rm -f to clear profile"
  else
    fail "activation clear must use nix-env --uninstall or rm -f to clear profile ($NS_MODULE)"
  fi

  # Activation only clears — must not trigger a build. Scoped to the
  # nix-scout-clear block itself: nixos-module.nix legitimately contains
  # `nix build` elsewhere (the switch-path activation script).
  if [[ -z "$CLEAR_BLOCK" ]]; then
    fail "could not isolate the nix-scout-clear activationScripts block ($NS_MODULE)"
  elif printf '%s' "$CLEAR_BLOCK" | "$GREP" -qE 'nix build|nix-build'; then
    fail "activation clear must not run nix build (activation only clears; switch builds)"
  else
    pass "activation clear does not contain nix build / nix-build"
  fi

  echo "-- nix-scout-update-locks: activation-safe getent + bash --"
  if "$GREP" -q 'activationScripts\.nix-scout-update-locks' "$NS_MODULE"; then
    pass "system.activationScripts.nix-scout-update-locks defined"
  else
    fail "activation must define nix-scout-update-locks ($NS_MODULE)"
  fi
  LOCKS_BLOCK="$(awk '/system\.activationScripts\.nix-scout-update-locks = \{/{f=1} f{print} f && /^  \};/{exit}' "$NS_MODULE")"
  if [[ -z "$LOCKS_BLOCK" ]]; then
    fail "could not isolate the nix-scout-update-locks activationScripts block ($NS_MODULE)"
  elif printf '%s' "$LOCKS_BLOCK" | "$GREP" -qE 'coreutils.*/bin/getent|pkgs\.coreutils\}/bin/getent'; then
    fail "update-locks must not use coreutils/bin/getent (getent is pkgs.getent)"
  elif ! printf '%s' "$LOCKS_BLOCK" | "$GREP" -qE 'pkgs\.getent|/bin/getent'; then
    fail "update-locks must invoke getent via pkgs.getent"
  elif ! printf '%s' "$LOCKS_BLOCK" | "$GREP" -qE 'pkgs\.bash\}/bin/bash|bash\}/bin/bash'; then
    fail "update-locks must invoke nix-scout via absolute pkgs.bash (activation PATH has no bash)"
  else
    pass "update-locks uses pkgs.getent and absolute bash"
  fi
else
  fail "nixos-module.nix not found at $NS_MODULE (cannot verify activation clear)"
fi

finish_suite
