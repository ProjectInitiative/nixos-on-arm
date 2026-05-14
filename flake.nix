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
      nanopir6s = {
        hostPlatform = "aarch64-linux";
        bootOnlyFile = ./boot/nanopi-r6s-boot.nix;
        demoFile = ./demo/nanopi-r6s-demo.nix;
        description = "FriendlyElec NanoPi R6S (RK3588S)";
      };
      renegade = {
        hostPlatform = "aarch64-linux";
        bootOnlyFile = ./boot/renegade-boot.nix;
        demoFile = ./demo/renegade-demo.nix;
        description = "ROC-RK3328-CC Renegade (RK3328)";
      };
    };

    # Function to create nixosConfiguration
    # buildSystem is the platform running the build (e.g., "x86_64-linux" or "aarch64-linux").
    # hostPlatform is always set to the board's target.
    # We do NOT set buildPlatform globally — only the kernel is cross-compiled
    # via a dedicated linuxPackagesCross set in *-cross variants.
    mkBoardConfiguration = board: buildSystem: modules:
      let
        hostPkgs = nixpkgs.legacyPackages.${buildSystem};
      in
      nixpkgs.lib.nixosSystem {
        specialArgs = { inherit hostPkgs; };
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

      "${board}-demo-cross" =
        mkBoardConfiguration board boards.${board}.hostPlatform
          (self.demoModules.${board} ++ [({ pkgs, lib, ... }: {
            boot.kernelPackages = lib.mkOverride 40 self.linuxPackagesCross.x86_64-linux;
          })]);

      "${board}-boot-cross" =
        mkBoardConfiguration board boards.${board}.hostPlatform
          (self.bootModules.${board} ++ [({ pkgs, lib, ... }: {
            boot.kernelPackages = lib.mkOverride 40 self.linuxPackagesCross.x86_64-linux;
          })]);
    };
  in
  {
    overlays.default = import ./overlays/uboot;

    # Kernel packages patched for Rockchip SoC quirks
    # Consumers can pin to this to share the same cached kernel build
    linuxPackages = forAllSystems (system:
      let
        pkgs = nixpkgs.legacyPackages.${system};
        rk3588Patch = ./modules/patches/0001-phy-rockchip-naneng-combphy-Add-PCIe-PHY-tuning-for-RK3588.patch;
        patchedKernel = pkgs.linuxPackages.kernel.override {
          extraConfig = ''
            FW_LOADER_COMPRESS y
            FW_LOADER_COMPRESS_ZSTD y
          '';
          kernelPatches = (pkgs.linuxPackages.kernel.kernelPatches or []) ++ [{
            name = "rk3588-combphy-pcie-tuning";
            patch = rk3588Patch;
          }];
        };
      in
      pkgs.linuxPackagesFor patchedKernel
    );

    # Cross-compiled kernel packages (x86_64 → aarch64) for *-cross variants.
    # Built on x86_64, outputs aarch64 kernel. Only the kernel is cross-compiled;
    # all other packages remain native aarch64 (pulled from cache or QEMU).
    linuxPackagesCross = forAllSystems (system:
      let
        pkgs = nixpkgs.legacyPackages.${system};
        crossPkgs = pkgs.pkgsCross.aarch64-multiplatform;
        rk3588Patch = ./modules/patches/0001-phy-rockchip-naneng-combphy-Add-PCIe-PHY-tuning-for-RK3588.patch;
        patchedKernel = crossPkgs.linuxPackages.kernel.override {
          extraConfig = ''
            FW_LOADER_COMPRESS y
            FW_LOADER_COMPRESS_ZSTD y
          '';
          kernelPatches = (crossPkgs.linuxPackages.kernel.kernelPatches or []) ++ [{
            name = "rk3588-combphy-pcie-tuning";
            patch = rk3588Patch;
          }];
        };
      in
      crossPkgs.linuxPackagesFor patchedKernel
    );

    # Barebones board modules (no users/network)
    bootModules = nixpkgs.lib.mapAttrs
      (name: board: [
        board.bootOnlyFile
        ({ pkgs, lib, ... }: {
          nixpkgs.overlays = [ self.overlays.default ];
          nixpkgs.hostPlatform = board.hostPlatform;
          nixpkgs.config.allowUnsupportedSystem = true;
          # Use nixos-on-arm's patched kernel automatically
          boot.kernelPackages = lib.mkForce self.linuxPackages.${pkgs.stdenv.hostPlatform.system};
        })
      ])
      boards;

    # Same for demo modules
    demoModules = nixpkgs.lib.mapAttrs
      (name: board: [
        board.demoFile
        ({ pkgs, lib, ... }: {
          nixpkgs.overlays = [ self.overlays.default ];
          nixpkgs.hostPlatform = board.hostPlatform;
          nixpkgs.config.allowUnsupportedSystem = true;
          nixpkgs.config.allowUnfree = true;
          boot.kernelPackages = lib.mkDefault self.linuxPackages.${pkgs.stdenv.hostPlatform.system};
        })
      ])
      boards;

    # Full nixosConfigurations (boot + demo variants)
    nixosConfigurations =
      (mkBoardConfigurations "e52c") //
      (mkBoardConfigurations "rock5a") //
      (mkBoardConfigurations "orangepi5ultra") //
      (mkBoardConfigurations "nanopir6s") //
      (mkBoardConfigurations "renegade");

    # System-specific packages organized by board
    packages = forAllSystems (system:
      let
        mkImg = board: modules:
          (mkBoardConfiguration board system modules).config.system.build.rockchipImages;
        mkCrossImg = board: modules:
          (mkBoardConfiguration board system (modules ++ [({ pkgs, lib, ... }: {
            boot.kernelPackages = lib.mkOverride 40 self.linuxPackagesCross.x86_64-linux;
          })])).config.system.build.rockchipImages;
      in {
        # --- E52C ---
        e52c = mkImg "e52c" self.demoModules.e52c;   # alias → demo
        e52c-demo = mkImg "e52c" self.demoModules.e52c;
        e52c-boot = mkImg "e52c" self.bootModules.e52c;
        e52c-demo-cross = mkCrossImg "e52c" self.demoModules.e52c;
        e52c-boot-cross = mkCrossImg "e52c" self.bootModules.e52c;

        # --- Rock5A ---
        rock5a = mkImg "rock5a" self.demoModules.rock5a; # alias → demo
        rock5a-demo = mkImg "rock5a" self.demoModules.rock5a;
        rock5a-boot = mkImg "rock5a" self.bootModules.rock5a;
        rock5a-demo-cross = mkCrossImg "rock5a" self.demoModules.rock5a;
        rock5a-boot-cross = mkCrossImg "rock5a" self.bootModules.rock5a;

        # --- Orange Pi 5 Ultra ---
        orangepi5ultra = mkImg "orangepi5ultra" self.demoModules.orangepi5ultra; # alias → demo
        orangepi5ultra-demo = mkImg "orangepi5ultra" self.demoModules.orangepi5ultra;
        orangepi5ultra-boot = mkImg "orangepi5ultra" self.bootModules.orangepi5ultra;
        orangepi5ultra-demo-cross = mkCrossImg "orangepi5ultra" self.demoModules.orangepi5ultra;
        orangepi5ultra-boot-cross = mkCrossImg "orangepi5ultra" self.bootModules.orangepi5ultra;

        # --- NanoPi R6S ---
        nanopir6s = mkImg "nanopir6s" self.demoModules.nanopir6s; # alias → demo
        nanopir6s-demo = mkImg "nanopir6s" self.demoModules.nanopir6s;
        nanopir6s-boot = mkImg "nanopir6s" self.bootModules.nanopir6s;
        nanopir6s-demo-cross = mkCrossImg "nanopir6s" self.demoModules.nanopir6s;
        nanopir6s-boot-cross = mkCrossImg "nanopir6s" self.bootModules.nanopir6s;

        # --- ROC-RK3328-CC Renegade ---
        renegade = mkImg "renegade" self.demoModules.renegade;   # alias → demo
        renegade-demo = mkImg "renegade" self.demoModules.renegade;
        renegade-boot = mkImg "renegade" self.bootModules.renegade;
        renegade-demo-cross = mkCrossImg "renegade" self.demoModules.renegade;
        renegade-boot-cross = mkCrossImg "renegade" self.bootModules.renegade;
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
          echo "Native (emulated) builds — nix build .#<board>-<variant>:"
          echo "  e52c-boot   # QEMU-emulated aarch64 kernel (~6h)"
          echo "  e52c-demo   # Demo with users/network"
          echo "  rock5a-boot"
          echo "  rock5a-demo"
          echo "  orangepi5ultra-{boot,demo}"
          echo "  nanopir6s-{boot,demo}"
          echo "  renegade-{boot,demo}"
          echo ""
          echo "Cross-compiled builds (fast, x86_64 → aarch64) — nix build .#<board>-<variant>-cross:"
          echo "  e52c-boot-cross   # ~1h instead of ~6h"
          echo "  e52c-demo-cross"
          echo "  rock5a-boot-cross"
          echo "  rock5a-demo-cross"
          echo "  orangepi5ultra-{boot,demo}-cross"
          echo "  nanopir6s-{boot,demo}-cross"
          echo "  renegade-{boot,demo}-cross"
        '';
      };
    });
  };
}
