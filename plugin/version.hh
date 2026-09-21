// Compile-time Nix version gate for the nix-scout plugin-files shim.
//
// Supported range: Nix 2.34 through 2.36 (exclusive upper bound 2.37).
// The RegisterCommand / Command API we use is stable across that window;
// CppNix 2.34+ ships nix-cmd with -std=c++23. Bump the max after verifying
// a newer minor against plugin/scout.cc.
//
// NIX_SCOUT_PLUGIN_NIX_{MAJOR,MINOR} must be passed by the build (from
// pkg-config / the nix package version being compiled against).

#pragma once

#ifndef NIX_SCOUT_PLUGIN_NIX_MAJOR
#error "NIX_SCOUT_PLUGIN_NIX_MAJOR must be defined by the build"
#endif
#ifndef NIX_SCOUT_PLUGIN_NIX_MINOR
#error "NIX_SCOUT_PLUGIN_NIX_MINOR must be defined by the build"
#endif

#define NIX_SCOUT_PLUGIN_MIN_MAJOR 2
#define NIX_SCOUT_PLUGIN_MIN_MINOR 34
#define NIX_SCOUT_PLUGIN_MAX_MAJOR 2
#define NIX_SCOUT_PLUGIN_MAX_MINOR 37 /* exclusive */

#define NIX_SCOUT_PLUGIN_VERSION_CODE(major, minor) ((major) * 1000 + (minor))

#define NIX_SCOUT_PLUGIN_NIX_CODE                                               \
  NIX_SCOUT_PLUGIN_VERSION_CODE(NIX_SCOUT_PLUGIN_NIX_MAJOR,                     \
                                NIX_SCOUT_PLUGIN_NIX_MINOR)
#define NIX_SCOUT_PLUGIN_MIN_CODE                                               \
  NIX_SCOUT_PLUGIN_VERSION_CODE(NIX_SCOUT_PLUGIN_MIN_MAJOR,                     \
                                NIX_SCOUT_PLUGIN_MIN_MINOR)
#define NIX_SCOUT_PLUGIN_MAX_CODE                                               \
  NIX_SCOUT_PLUGIN_VERSION_CODE(NIX_SCOUT_PLUGIN_MAX_MAJOR,                     \
                                NIX_SCOUT_PLUGIN_MAX_MINOR)

#if NIX_SCOUT_PLUGIN_NIX_CODE < NIX_SCOUT_PLUGIN_MIN_CODE
#error nix-scout plugin: Nix version is below the supported range (need >= 2.34)
#endif
#if NIX_SCOUT_PLUGIN_NIX_CODE >= NIX_SCOUT_PLUGIN_MAX_CODE
#error nix-scout plugin: Nix version is above the supported range (need < 2.37; re-verify RegisterCommand and bump MAX)
#endif
