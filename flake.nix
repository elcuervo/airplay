{
  description = "AirPlay sender for Ruby 4";

  inputs.nixpkgs.url = "nixpkgs";

  outputs = { self, nixpkgs }:
    let
      system = "aarch64-darwin";
      pkgs = nixpkgs.legacyPackages.${system};
      shellHook = ''
        export GEM_HOME="$PWD/.nix/gems"
        export GEM_PATH="$GEM_HOME"
        export BUNDLE_PATH="$GEM_HOME"
        export BUNDLE_APP_CONFIG="$PWD/.nix/bundle"
        mkdir -p "$GEM_HOME" "$BUNDLE_APP_CONFIG"
      '';
    in
    {
      devShells.${system}.default = pkgs.mkShell {
        packages = with pkgs; [
          ruby_4_0
          openssl
          pkg-config
          jq
          git
        ];
        inherit shellHook;
      };
    };
}
