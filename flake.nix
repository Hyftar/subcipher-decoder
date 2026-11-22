{
  description = "Subcipher: substitution cipher workbench (Elixir / Phoenix LiveView)";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs = { nixpkgs, ... }:
    let
      systems = [ "x86_64-linux" "aarch64-linux" "x86_64-darwin" "aarch64-darwin" ];
      forAllSystems = f: nixpkgs.lib.genAttrs systems (system: f nixpkgs.legacyPackages.${system});
    in
    {
      # Same environment as `nix-shell` (see shell.nix).
      devShells = forAllSystems (pkgs: { default = import ./shell.nix { inherit pkgs; }; });
    };
}
