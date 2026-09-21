{
  lib,
  stdenv,
  pkg-config,
  # ABI must match the nix that dlopen()s this plugin (config.nix.package).
  nix-cmd,
  nlohmann_json,
}:

stdenv.mkDerivation (finalAttrs: {
  pname = "nix-scout-plugin";
  version = "0.8.0";

  src = lib.fileset.toSource {
    root = ./.;
    fileset = lib.fileset.unions [
      ./scout.cc
      ./version.hh
    ];
  };

  nativeBuildInputs = [ pkg-config ];

  # Headers only at build time. Do not DT_NEEDED-link nix libs — the host nix
  # process already provides them (see man nix.conf plugin-files). Linking a
  # second copy breaks RegisterCommand's static map (same trap as nix-tarmac).
  buildInputs = [
    nix-cmd
    nlohmann_json
  ];

  dontConfigure = true;

  # pkg-config Version is like "2.34.8" or "2.35.0pre…".
  nixMajor = lib.versions.major nix-cmd.version;
  nixMinor = lib.versions.minor nix-cmd.version;

  buildPhase = ''
    runHook preBuild
    major=${finalAttrs.nixMajor}
    minor=${finalAttrs.nixMinor}
    echo "nix-scout-plugin: compiling against Nix $major.$minor (${nix-cmd.version})"
    $CXX -std=c++23 -shared -fPIC scout.cc -o nix-scout.so \
      $(pkg-config --cflags nix-cmd) \
      -DNIX_SCOUT_PLUGIN_NIX_MAJOR=$major \
      -DNIX_SCOUT_PLUGIN_NIX_MINOR=$minor \
      -Wl,--unresolved-symbols=ignore-all
    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall
    install -Dm755 nix-scout.so "$out/lib/nix/plugins/nix-scout.so"
    runHook postInstall
  '';

  meta = {
    description = "nix plugin-files shim that registers `nix scout`";
    license = lib.licenses.mit;
  };
})
