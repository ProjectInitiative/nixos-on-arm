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
    # Supported build systems
    supportedSystems = [ "x86_64-linux" "aarch64-linux" ];
    
    # Helper to generate attrs for each system
    forAllSystems = nixpkgs.lib.genAttrs supportedSystems;
    
    # Board configurations
    boards = {
      e52c = {
        hostPlatform = "aarch64-linux";
        configFile = ./e52c-configuration.nix;
        description = "Radxa E52C (RK3582)";
      };
      # Future boards can be added here:
      # e25 = {
      #   hostPlatform = "aarch64-linux";
      #   configFile = ./e25-configuration.nix;
      #   description = "Radxa E25 (RK3568)";
      # };
      # rock5b = {
      #   hostPlatform = "aarch64-linux";
      #   configFile = ./rock5b-configuration.nix;
      #   description = "Radxa Rock 5B (RK3588)";
      # };
    };
    
    # Function to create nixosConfiguration for a given board and build system
    mkBoardConfiguration = board: buildSystem: nixpkgs.lib.nixosSystem {
      system = buildSystem;
      modules = [
        # Import the board-specific configuration
        boards.${board}.configFile
        
        # Apply the U-Boot overlay
        ({ config, pkgs, ... }: {
          nixpkgs.overlays = [ self.overlays.default ];
          
          # Set platforms based on build system
          nixpkgs.buildPlatform = buildSystem;
          nixpkgs.hostPlatform = boards.${board}.hostPlatform;
          
          # Enable cross-compilation features when needed
          nixpkgs.config = {
            allowUnsupportedSystem = true;
          } // (if buildSystem != boards.${board}.hostPlatform then {
            # Additional cross-compilation config for non-native builds
            allowUnfree = true;
          } else {});
        })
      ];
    };
    
    # Generate nixosConfigurations for all boards
    mkBoardConfigurations = board: {
      "${board}" = mkBoardConfiguration board boards.${board}.hostPlatform;
      "${board}-native" = mkBoardConfiguration board boards.${board}.hostPlatform;
      "${board}-cross" = mkBoardConfiguration board "x86_64-linux";
    };
  in
  {
    overlays.default = import ./overlays/uboot;

    # Create configurations for all boards
    nixosConfigurations = nixpkgs.lib.mergeAttrs 
      (mkBoardConfigurations "e52c")
      {
        # Add more boards here as you create them:
        # inherit (mkBoardConfigurations "e25") e25 e25-native e25-cross;
        # inherit (mkBoardConfigurations "rock5b") rock5b rock5b-native rock5b-cross;
      };

    # System-specific packages organized by board
    packages = forAllSystems (system: 
      let
        # Generate packages for a specific board
        mkBoardPackages = board: {
          # Auto-detect: use current system as build platform
          "${board}" = (mkBoardConfiguration board system).config.system.build.rockchipImages;
          "${board}-default" = (mkBoardConfiguration board system).config.system.build.rockchipImages;
          
          # Explicit build modes (available on all systems)
          "${board}-native" = self.nixosConfigurations.${board}-native.config.system.build.rockchipImages;
          "${board}-cross" = self.nixosConfigurations.${board}-cross.config.system.build.rockchipImages;
          
          # Aliases for backward compatibility and convenience
          "${board}-images" = (mkBoardConfiguration board system).config.system.build.rockchipImages;
        };
      in
      nixpkgs.lib.mergeAttrs 
        (mkBoardPackages "e52c")
        {
          # Default points to e52c for backward compatibility
          default = (mkBoardConfiguration "e52c" system).config.system.build.rockchipImages;
          
          # Add more boards here:
          # inherit (mkBoardPackages "e25") e25 e25-default e25-native e25-cross e25-images;
          # inherit (mkBoardPackages "rock5b") rock5b rock5b-default rock5b-native rock5b-cross rock5b-images;
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
          echo "  nix build .#e52c                    # Auto-detect build system"
          echo "  nix build .#e52c-cross              # Cross-compile from x86_64" 
          echo "  nix build .#e52c-native             # Native ARM build"
          echo ""
          echo "Future boards will follow the same pattern:"
          echo "  nix build .#e25, .#rock5b, etc."
        '';
      };
    });
  };
}
