{
  pkgs ? (
    let
      lock = builtins.fromJSON (builtins.readFile ./flake.lock);
    in
    import (builtins.fetchTarball {
      url = "https://github.com/NixOS/nixpkgs/archive/${lock.nodes.nixpkgs.locked.rev}.tar.gz";
      sha256 = lock.nodes.nixpkgs.locked.narHash;
    }) { }
  ),
}:

let
  # Cross-platform deps. Build toolchain + ops validation tools — these all
  # work identically on linux and darwin.
  commonDeps = with pkgs; [
    dotnet-sdk_10
    python3
    pre-commit
    nixfmt
    # VS - ops validation tools (pinned for reproducible subagent/contributor env)
    shellcheck
    yamllint
    prometheus # provides promtool
    grafana-loki # provides loki + logcli
    grafana # provides grafana-cli
    postgresql_17 # provides psql/pg_dump/pg_restore/createdb (matches services-flake server)
    # VS - bundled-service build toolchain (vs-1vy cookbook, vs-236 mapviewer,
    # vs-v69 document-simu — all node/vite-based static sites)
    nodejs_20
    rsync
  ];

  # Linux-only client runtime: graphics (X11/Wayland/mesa), audio (ALSA),
  # gtk/atk/glib accessibility stack, libdrm. These pull an X11 dep chain
  # that does not build on darwin. Server-only dev on darwin skips them.
  linuxDeps = with pkgs; [
    icu
    glfw
    libGL
    openal
    freetype
    fluidsynth
    soundfont-fluid
    gtk3
    pango
    cairo
    atk
    zlib
    glib
    gdk-pixbuf
    nss
    nspr
    at-spi2-atk
    libdrm
    expat
    libxkbcommon
    xorg.libxcb
    xorg.libX11
    xorg.libXcomposite
    xorg.libXdamage
    xorg.libXext
    xorg.libXfixes
    xorg.libXrandr
    xorg.libxshmfence
    mesa
    alsa-lib
    dbus
    at-spi2-core
    cups
    wayland
  ];

  # Darwin: no client-runtime deps here. Content.Client on macOS links
  # against Apple frameworks (Metal, CoreAudio) at build time, not via
  # nix-packaged libraries. macOS contributors needing to RUN the client
  # should use a Linux VM — the darwin dev shell is server-only.
  darwinDeps = [ ];

  dependencies =
    commonDeps
    ++ pkgs.lib.optionals pkgs.stdenv.isLinux linuxDeps
    ++ pkgs.lib.optionals pkgs.stdenv.isDarwin darwinDeps;
in
pkgs.mkShell {
  name = "space-station-14-devshell";
  packages = dependencies;
  shellHook = ''
    ${pkgs.lib.optionalString pkgs.stdenv.isLinux ''
      export GLIBC_TUNABLES=glibc.rtld.dynamic_sort=1
      export ROBUST_SOUNDFONT_OVERRIDE=${pkgs.soundfont-fluid}/share/soundfonts/FluidR3_GM2-2.sf2
      export XDG_DATA_DIRS=$GSETTINGS_SCHEMAS_PATH
      export LD_LIBRARY_PATH=${pkgs.lib.makeLibraryPath dependencies}
    ''}
  '';
}
