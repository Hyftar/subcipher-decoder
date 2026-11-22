{ pkgs ? import <nixpkgs> { } }:

let
  beamPackages = pkgs.beam.packages.erlang_28;
  elixir = beamPackages.elixir_1_19;
in
pkgs.mkShell {
  packages = [
    beamPackages.erlang
    elixir
    beamPackages.hex
    beamPackages.rebar3

    # Asset tooling. Phoenix normally downloads prebuilt esbuild/tailwind
    # binaries, which don't run on NixOS, so we point mix at the nix ones.
    pkgs.esbuild
    pkgs.tailwindcss_4
    pkgs.nodejs # only used to run the JS unit tests

    pkgs.postgresql # psql client only, the server runs in Docker
    pkgs.docker-compose
    pkgs.imagemagick # used to generate test fixtures
    pkgs.gnumake
  ] ++ pkgs.lib.optionals pkgs.stdenv.isLinux [ pkgs.inotify-tools ];

  shellHook = ''
    export MIX_HOME="$PWD/.nix-mix"
    export HEX_HOME="$PWD/.nix-hex"
    export MIX_REBAR3="${beamPackages.rebar3}/bin/rebar3"
    export PATH="$MIX_HOME/bin:$MIX_HOME/escripts:$HEX_HOME/bin:$PATH"
    export ERL_AFLAGS="-kernel shell_history enabled"

    export MIX_ESBUILD_PATH="${pkgs.esbuild}/bin/esbuild"
    export MIX_TAILWIND_PATH="${pkgs.tailwindcss_4}/bin/tailwindcss"
    export MIX_ESBUILD_VERSION="${pkgs.esbuild.version}"
    export MIX_TAILWIND_VERSION="${pkgs.tailwindcss_4.version}"

    # The database container must run on the local Docker daemon
    # (the app connects to localhost).
    export DOCKER_CONTEXT=default

    export LANG=C.UTF-8
  '';
}
