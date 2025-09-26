{
  description = "NixOS flake for Rockchip ARM boards";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    disko = {
      url = "github:nix-community/disko";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, disko }:
  let
    supportedSystems = [ "x86_64-linux" "aarch64-linux" ];
    forAllSystems = nixpkgs.lib.genAttrs supportedSystems;

    boards = {
      e52c = {
        hostPlatform = "aarch64-linux";
        bootOnlyFile = ./boot/e52c-boot.nix;
        demoFile = ./demo/e52c-demo.nix;
        description = "Radxa E52C (RK3582)";
      };
      rock5a = {
        hostPlatform = "aarch64-linux";
        bootOnlyFile = ./boot/rock5a-boot.nix;
        demoFile = ./demo/rock5a-demo.nix;
        description = "Radxa Rock5A (RK3588s)";
      };
      orangepi5ultra = {
        hostPlatform = "aarch64-linux";
        bootOnlyFile = ./boot/orange-pi-5-ultra-boot.nix;
        demoFile = ./demo/orange-pi-5-ultra-demo.nix;
        description = "Orange Pi 5 Ultra (RK3588)";
      };
    };

    # Function to create nixosConfiguration
    mkBoardConfiguration = board: buildSystem: modules:
      nixpkgs.lib.nixosSystem {
        system = buildSystem;
        modules = modules ++ [
          ({ pkgs, ... }: {
            nixpkgs.overlays = [ self.overlays.default ];
            nixpkgs.hostPlatform = boards.${board}.hostPlatform;
            nixpkgs.config.allowUnsupportedSystem = true;
          })
        ];
      };

    mkBoardConfigurations = board: {
      "${board}-demo" =
        mkBoardConfiguration board boards.${board}.hostPlatform
          (self.demoModules.${board});

      "${board}-boot" =
        mkBoardConfiguration board boards.${board}.hostPlatform
          (self.bootModules.${board});

      # Optionally, also export cross builds
      "${board}-cross-demo" =
        mkBoardConfiguration board "x86_64-linux"
          (self.demoModules.${board});
    };
  in
  {
    overlays.default = import ./overlays/uboot;

    # Barebones board modules (no users/network)
    bootModules = nixpkgs.lib.mapAttrs
      (name: board: [
        board.bootOnlyFile
        ({ pkgs, ... }: {
          nixpkgs.overlays = [ self.overlays.default ];
          nixpkgs.hostPlatform = board.hostPlatform;
          nixpkgs.config.allowUnsupportedSystem = true;
        })
      ])
      boards;

    # Demo modules (insecure, dev-only)
    demoModules = nixpkgs.lib.mapAttrs
      (name: board: [
        board.demoFile
        ({ pkgs, ... }: {
          nixpkgs.overlays = [ self.overlays.default ];
          nixpkgs.hostPlatform = board.hostPlatform;
          nixpkgs.config.allowUnsupportedSystem = true;
          nixpkgs.config.allowUnfree = true;
        })
      ])
      boards;

    # Full nixosConfigurations (boot + demo variants)
    nixosConfigurations =
      (mkBoardConfigurations "e52c") //
      (mkBoardConfigurations "rock5a") //
      (mkBoardConfigurations "orangepi5ultra");

    # System-specific packages organized by board
    packages = forAllSystems (system:
      let
        mkImg = board: modules:
          (mkBoardConfiguration board system modules).config.system.build.rockchipImages;
      in {
        # --- E52C ---
        e52c = mkImg "e52c" self.demoModules.e52c;   # alias → demo
        e52c-demo = mkImg "e52c" self.demoModules.e52c;
        e52c-boot = mkImg "e52c" self.bootModules.e52c;

        # --- Rock5A ---
        rock5a = mkImg "rock5a" self.demoModules.rock5a; # alias → demo
        rock5a-demo = mkImg "rock5a" self.demoModules.rock5a;
        rock5a-boot = mkImg "rock5a" self.bootModules.rock5a;

        # --- Orange Pi 5 Ultra ---
        orangepi5ultra = mkImg "orangepi5ultra" self.demoModules.orangepi5ultra; # alias → demo
        orangepi5ultra-demo = mkImg "orangepi5ultra" self.demoModules.orangepi5ultra;
        orangepi5ultra-boot = mkImg "orangepi5ultra" self.bootModules.orangepi5ultra;
      }
    );

    # Development shells
    devShells = forAllSystems (system: {
      default = nixpkgs.legacyPackages.${system}.mkShell {
        buildInputs = with nixpkgs.legacyPackages.${system}; [
          nixos-rebuild
          git
        ];

        shellHook = ''
          echo "Available boards: ${builtins.concatStringsSep ", " (builtins.attrNames boards)}"
          echo ""
          echo "Build commands:"
          echo "  nix build .#e52c        # Demo image (default alias)"
          echo "  nix build .#e52c-demo   # Explicit demo image"
          echo "  nix build .#e52c-boot   # Barebones boot-only image"
          echo ""
          echo "  nix build .#rock5a      # Demo image (default alias)"
          echo "  nix build .#rock5a-demo # Explicit demo image"
          echo "  nix build .#rock5a-boot # Barebones boot-only image"
          echo ""
          echo "  nix build .#orangepi5ultra      # Demo image (default alias)"
          echo "  nix build .#orangepi5ultra-demo # Explicit demo image"
          echo "  nix build .#orangepi5ultra-boot # Barebones boot-only image"
        '';
      };
    });
  };
}
