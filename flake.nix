{
  description = "AirPlay sender for Ruby 4";

  inputs.nixpkgs.url = "nixpkgs";

  outputs = { self, nixpkgs }:
    let
      systems = [ "aarch64-darwin" "x86_64-linux" "aarch64-linux" ];
      forAllSystems = f: nixpkgs.lib.genAttrs systems (system: f nixpkgs.legacyPackages.${system});

      shellHook = ''
        export GEM_HOME="$PWD/.nix/gems"
        export GEM_PATH="$GEM_HOME"
        export BUNDLE_PATH="$GEM_HOME"
        export BUNDLE_APP_CONFIG="$PWD/.nix/bundle"
        mkdir -p "$GEM_HOME" "$BUNDLE_APP_CONFIG"
      '';

      base = pkgs: with pkgs; [
        ruby_4_0
        openssl
        pkg-config
        jq
        git
      ];

      simulators = pkgs: with pkgs; [
        ffmpeg
        avahi
        uxplay
      ] ++ nixpkgs.lib.optionals pkgs.stdenv.hostPlatform.isLinux [
        shairport-sync
        owntone
      ];
    in
    {
      devShells = forAllSystems (pkgs: {
        default = pkgs.mkShell {
          packages = base pkgs;
          inherit shellHook;
        };
        integration = pkgs.mkShell {
          packages = base pkgs ++ simulators pkgs;
          inherit shellHook;
        };
      });
    };
}
