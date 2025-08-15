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

      rock5a = {
        hostPlatform = "aarch64-linux";
        configFile = ./rock5a-configuration.nix;
        description = "Radxa Rock5A (RK3588s)";
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
      (mkBoardConfigurations "rock5a")
      {
        # Add more boards here as you create them:
        # inherit (mkBoardConfigurations "e25") e25 e25-native e25-cross;
        # inherit (mkBoardConfigurations "rock5b") rock5b rock5b-native rock5b-cross;
      };

    # System-specific packages organized by board
    packages = forAllSystems (system: 
      let
        # Direct references to avoid interpolation issues
        e52cNative = self.nixosConfigurations.e52c-native.config.system.build.rockchipImages;
        e52cCross = self.nixosConfigurations.e52c-cross.config.system.build.rockchipImages;
        rock5aNative = self.nixosConfigurations.rock5a-native.config.system.build.rockchipImages;
        rock5aCross = self.nixosConfigurations.rock5a-cross.config.system.build.rockchipImages;
      in
      {
        # E52C builds
        e52c = (mkBoardConfiguration "e52c" system).config.system.build.rockchipImages;
        e52c-default = (mkBoardConfiguration "e52c" system).config.system.build.rockchipImages;
        e52c-native = e52cNative;
        e52c-cross = e52cCross;
        e52c-images = (mkBoardConfiguration "e52c" system).config.system.build.rockchipImages;
        
        rock5a = (mkBoardConfiguration "rock5a" system).config.system.build.rockchipImages;
        rock5a-default = (mkBoardConfiguration "rock5a" system).config.system.build.rockchipImages;
        rock5a-native = rock5aNative;
        rock5a-cross = rock5aCross;
        rock5a-images = (mkBoardConfiguration "rock5a" system).config.system.build.rockchipImages;
        # Future boards can be added here:
        # e25 = (mkBoardConfiguration "e25" system).config.system.build.rockchipImages;
        # e25-native = self.nixosConfigurations.e25-native.config.system.build.rockchipImages;
        # e25-cross = self.nixosConfigurations.e25-cross.config.system.build.rockchipImages;
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
