#!/usr/bin/env bash
# Plugin-files shim + completions/wiring parity for `nix scout`.
set -euo pipefail

# shellcheck source=_lib.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/_lib.sh"

echo "== nix-scout plugin shim =="

TSV="$REPO/share/subcommands.tsv"
PLUGIN_CC="$REPO/plugin/scout.cc"
VERSION_HH="$REPO/plugin/version.hh"
FLAKE="$REPO/flake.nix"
MODULE="$REPO/nixos-module.nix"
WRAP="$REPO/bin/nix-wrap.sh"
CLI="$REPO/bin/nix-scout"

if [[ -f "$TSV" ]]; then
  pass "share/subcommands.tsv exists"
else
  fail "share/subcommands.tsv missing (subcommand source of truth)"
fi

mapfile -t TSV_NAMES < <(awk -F'\t' 'NF && $1 !~ /^#/ { print $1 }' "$TSV")
if [[ "${#TSV_NAMES[@]}" -ge 8 ]]; then
  pass "subcommands.tsv lists ${#TSV_NAMES[@]} commands"
else
  fail "subcommands.tsv too short (${#TSV_NAMES[@]} entries)"
fi

echo "-- plugin embeds the same subcommand names --"
for name in "${TSV_NAMES[@]}"; do
  if "$GREP" -q "\"$name\"" "$PLUGIN_CC"; then
    pass "plugin/scout.cc embeds \"$name\""
  else
    fail "plugin/scout.cc missing subcommand \"$name\" (keep kSubcommands ↔ subcommands.tsv)"
  fi
done

# Every string literal in kSubcommands must appear in the TSV (no extras).
mapfile -t PLUGIN_NAMES < <(
  awk '
    /kSubcommands\[\]/,/\};/ {
      while (match($0, /"([^"]+)"/, m)) {
        print m[1]
        $0 = substr($0, RSTART + RLENGTH)
      }
    }
  ' "$PLUGIN_CC"
)
for name in "${PLUGIN_NAMES[@]}"; do
  found=0
  for t in "${TSV_NAMES[@]}"; do
    if [[ "$t" == "$name" ]]; then found=1; break; fi
  done
  if [[ "$found" -eq 1 ]]; then
    pass "plugin name \"$name\" is in subcommands.tsv"
  else
    fail "plugin name \"$name\" not in subcommands.tsv"
  fi
done

if [[ "${#PLUGIN_NAMES[@]}" -eq "${#TSV_NAMES[@]}" ]]; then
  pass "plugin and TSV have the same subcommand count (${#TSV_NAMES[@]})"
else
  fail "plugin has ${#PLUGIN_NAMES[@]} names, TSV has ${#TSV_NAMES[@]}"
fi

echo "-- CLI completions mention every TSV subcommand --"
STRICT_BIN=""
if STRICT_BIN="$(resolve_strict_nix_scout)"; then
  pass "resolved nix-scout at $STRICT_BIN"
else
  fail "nix-scout binary missing"
  finish_suite
fi

for shell in fish bash zsh; do
  run_capture "$STRICT_BIN" completions "$shell"
  if [[ "$CAPTURED_RC" -ne 0 ]]; then
    fail "completions $shell failed"
    continue
  fi
  for name in "${TSV_NAMES[@]}"; do
    if [[ "$CAPTURED_OUT" == *"$name"* ]]; then
      pass "completions $shell mentions $name"
    else
      fail "completions $shell missing $name"
    fi
  done
done

echo "-- completions also wire nix scout (not only nix-scout) --"
run_capture "$STRICT_BIN" completions bash
if [[ "$CAPTURED_OUT" == *_nix_scout_nix_dispatch* ]] \
  && [[ "$CAPTURED_OUT" == *"complete -F _nix_scout_nix_dispatch nix"* ]]; then
  pass "bash completions register _nix_scout_nix_dispatch for \`nix\`"
else
  fail "bash completions must \`complete -F _nix_scout_nix_dispatch nix\` for nix-wrap"
fi
if [[ "$CAPTURED_OUT" == *'words[1]:-} == scout'* ]] \
  || [[ "$CAPTURED_OUT" == *'words[1]:-}'*'scout'* ]]; then
  pass "bash nix dispatch shifts past scout"
else
  fail "bash nix dispatch must special-case words[1]==scout"
fi
run_capture "$STRICT_BIN" completions fish
if [[ "$CAPTURED_OUT" == *complete\ -c\ nix* ]] || [[ "$CAPTURED_OUT" == *"complete -c nix"* ]]; then
  pass "fish completions register for command \`nix\`"
else
  fail "fish completions must include complete -c nix for scout"
fi
run_capture "$STRICT_BIN" completions zsh
if [[ "$CAPTURED_OUT" == *'#compdef'*nix-scout*nix* ]] \
  || [[ "$CAPTURED_OUT" == *compdef*nix-scout* ]]; then
  # zsh: either multi-compdef or a _nix that handles scout — accept scout-aware markers
  if [[ "$CAPTURED_OUT" == *scout* && "$CAPTURED_OUT" == *nix-scout* ]]; then
    pass "zsh completions cover nix-scout (scout-aware)"
  else
    fail "zsh completions incomplete"
  fi
else
  fail "zsh completions missing nix-scout compdef"
fi
# Stronger: zsh must mention forwarding/handling when words[1] is scout OR compdef nix
if [[ "$CAPTURED_OUT" == *'compdef nix-scout nix'* ]] \
  || [[ "$CAPTURED_OUT" == *"compdef nix-scout nix"* ]] \
  || [[ "$CAPTURED_OUT" == *'#compdef nix-scout nix'* ]]; then
  pass "zsh compdef includes nix (wrapper argv0)"
else
  fail "zsh must \`#compdef nix-scout nix\` so \`nix scout\` completes"
fi

echo "-- version gate constants --"
for tok in \
  'NIX_SCOUT_PLUGIN_MIN_MINOR 34' \
  'NIX_SCOUT_PLUGIN_MAX_MINOR 36' \
  'NIX_SCOUT_PLUGIN_MIN_MAJOR 2' \
  'NIX_SCOUT_PLUGIN_MAX_MAJOR 2'; do
  if "$GREP" -q "$tok" "$VERSION_HH"; then
    pass "version.hh has $tok"
  else
    fail "version.hh missing $tok"
  fi
done
if "$GREP" -q 'nix-scout plugin: Nix version is below' "$VERSION_HH" \
  && "$GREP" -q 'nix-scout plugin: Nix version is above' "$VERSION_HH"; then
  pass "version.hh #errors for out-of-range Nix"
else
  fail "version.hh must #error outside the supported range"
fi

echo "-- flake / module wiring --"
for tok in \
  'nix-scout-plugin' \
  'plugin-files' \
  'lib/nix/plugins/nix-scout.so' \
  'nix-wrap'; do
  if "$GREP" -q "$tok" "$FLAKE" || "$GREP" -q "$tok" "$MODULE"; then
    pass "wiring mentions $tok (flake or nixos-module)"
  else
    fail "flake.nix or nixos-module.nix must wire $tok"
  fi
done

if "$GREP" -q 'plugin-files' "$MODULE"; then
  pass "nixos-module.nix sets plugin-files"
else
  fail "nixos-module.nix must set nix.settings.plugin-files for the shim"
fi

if [[ -f "$WRAP" ]] && "$GREP" -q 'scout' "$WRAP" && "$GREP" -q 'REAL_NIX\|@real_nix@' "$WRAP"; then
  pass "bin/nix-wrap.sh forwards scout to nix-scout"
else
  fail "bin/nix-wrap.sh missing or incomplete"
fi

if "$GREP" -q 'registerCommand' "$PLUGIN_CC" && "$GREP" -q '"scout"' "$PLUGIN_CC"; then
  pass "plugin registers RegisterCommand(\"scout\")"
else
  fail "plugin must registerCommand<…>(\"scout\")"
fi

# usage() should still document nix-scout; optional note about nix scout is fine
if "$GREP" -q 'nix-scout list' "$CLI"; then
  pass "CLI usage still documents nix-scout"
else
  fail "CLI usage() missing"
fi

finish_suite
