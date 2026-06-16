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
        rk3588 = true;
      };
      orangepi5ultra = {
        hostPlatform = "aarch64-linux";
        bootOnlyFile = ./boot/orange-pi-5-ultra-boot.nix;
        demoFile = ./demo/orange-pi-5-ultra-demo.nix;
        description = "Orange Pi 5 Ultra (RK3588)";
        rk3588 = true;
      };
      nanopir6s = {
        hostPlatform = "aarch64-linux";
        bootOnlyFile = ./boot/nanopi-r6s-boot.nix;
        demoFile = ./demo/nanopi-r6s-demo.nix;
        description = "FriendlyElec NanoPi R6S (RK3588S)";
        rk3588 = true;
      };
      nanopir5s = {
        hostPlatform = "aarch64-linux";
        bootOnlyFile = ./boot/nanopi-r5s-boot.nix;
        demoFile = ./demo/nanopi-r5s-demo.nix;
        description = "FriendlyElec NanoPi R5S (RK3568)";
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
          ({ pkgs, lib, ... }: {
            nixpkgs.overlays = [ self.overlays.default ];
            nixpkgs.hostPlatform = boards.${board}.hostPlatform;
            nixpkgs.config.allowUnsupportedSystem = true;
            boot.zfs.forceImportRoot = lib.mkDefault false;
          })
        ];
      };

    # Shared kernel module used by most boards
    # Selects linuxPackagesRK3588 for boards with rk3588 flag, else linuxPackages
    mkKernelModule = board: { pkgs, lib, ... }: {
      nixpkgs.overlays = [ self.overlays.default ];
      nixpkgs.hostPlatform = board.hostPlatform;
      nixpkgs.config.allowUnsupportedSystem = true;
      boot.kernelPackages = lib.mkForce (
        if board ? rk3588
        then self.linuxPackagesRK3588.${pkgs.stdenv.hostPlatform.system}
        else self.linuxPackages.${pkgs.stdenv.hostPlatform.system}
      );
    };

    # Cross-compile kernel module — always uses the x86_64 cross kernel.
    # The cross package (linuxPackages*Cross) is keyed by the BUILD platform.
    # Since cross-compilation here is x86_64 → aarch64, we hardcode x86_64-linux.
    # Users building on aarch64 should use the native bootModules instead.
    mkCrossKernelModule = board: { pkgs, lib, ... }: {
      nixpkgs.overlays = [ self.overlays.default ];
      nixpkgs.hostPlatform = board.hostPlatform;
      nixpkgs.config.allowUnsupportedSystem = true;
      boot.kernelPackages = lib.mkOverride 40 (
        if board ? rk3588
        then self.linuxPackagesRK3588Cross.x86_64-linux
        else self.linuxPackagesCross.x86_64-linux
      );
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
          (self.demoModules.${board} ++ [ (mkCrossKernelModule boards.${board}) ]);

      "${board}-boot-cross" =
        mkBoardConfiguration board boards.${board}.hostPlatform
          (self.bootModules.${board} ++ [ (mkCrossKernelModule boards.${board}) ]);
    };
  in
  {
    overlays.default = import ./overlays/uboot;

    # Kernel packages patched for Rockchip SoC quirks
    # Consumers can pin to this to share the same cached kernel build
    linuxPackages = forAllSystems (system:
      let
        pkgs = nixpkgs.legacyPackages.${system};
        patchedKernel = pkgs.linuxPackages.kernel.override {
          extraConfig = ''
            FW_LOADER_COMPRESS y
            FW_LOADER_COMPRESS_ZSTD y
          '';
        };
      in
      pkgs.linuxPackagesFor patchedKernel
    );

    # Kernel packages for RK3588 boards (Orange Pi 5 Ultra, etc.)
    # Based on linuxPackages_latest with VEPU580 encoder and HDMI-RX patches
    linuxPackagesRK3588 = forAllSystems (system:
      let
        pkgs = nixpkgs.legacyPackages.${system};
      in
      import ./boot/kernels/orangepi5ultra/kernel.nix { inherit pkgs; lib = nixpkgs.lib; }
    );

    # Cross-compiled kernel packages (x86_64 → aarch64) for *-cross variants.
    # Built on x86_64, outputs aarch64 kernel. Only the kernel is cross-compiled;
    # all other packages remain native aarch64 (pulled from cache or QEMU).
    linuxPackagesCross = forAllSystems (system:
      let
        pkgs = nixpkgs.legacyPackages.${system};
        crossPkgs = pkgs.pkgsCross.aarch64-multiplatform;
        patchedKernel = crossPkgs.linuxPackages.kernel.override {
          extraConfig = ''
            FW_LOADER_COMPRESS y
            FW_LOADER_COMPRESS_ZSTD y
          '';
        };
      in
      crossPkgs.linuxPackagesFor patchedKernel
    );

    # Cross-compiled RK3588 kernel (x86_64 → aarch64) with VEPU580/HDMI-RX patches.
    # For Orange Pi 5 Ultra and similar boards that need board-specific kernel patches.
    linuxPackagesRK3588Cross = forAllSystems (system:
      let
        pkgs = nixpkgs.legacyPackages.${system};
        crossPkgs = pkgs.pkgsCross.aarch64-multiplatform;
      in
      import ./boot/kernels/orangepi5ultra/kernel.nix { pkgs = crossPkgs; lib = nixpkgs.lib; }
    );

    # Cross-compiled testing kernel (x86_64 → aarch64) for bleeding edge testing.
    # Uses linuxPackages_testing (e.g. 7.0-rc4) with stock defconfig.
    linuxPackagesTestingCross = forAllSystems (system:
      let
        pkgs = nixpkgs.legacyPackages.${system};
        crossPkgs = pkgs.pkgsCross.aarch64-multiplatform;
        patchedKernel = crossPkgs.linuxPackages_testing.kernel.override {
          extraConfig = ''
            FW_LOADER_COMPRESS y
            FW_LOADER_COMPRESS_ZSTD y
          '';
        };
      in
      crossPkgs.linuxPackagesFor patchedKernel
    );

    # Barebones board modules (no users/network)
    bootModules = nixpkgs.lib.mapAttrs
      (name: board: [
        board.bootOnlyFile
        (mkKernelModule board)
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
          boot.kernelPackages = lib.mkDefault (
            if board ? rk3588
            then self.linuxPackagesRK3588.${pkgs.stdenv.hostPlatform.system}
            else self.linuxPackages.${pkgs.stdenv.hostPlatform.system}
          );
        })
      ])
      boards;

    # Cross-compiled boot modules (x86_64 → aarch64 kernel)
    bootModulesCross = nixpkgs.lib.mapAttrs
      (name: board: [
        board.bootOnlyFile
        (mkCrossKernelModule board)
      ])
      boards;

    # Cross-compiled demo modules (x86_64 → aarch64 kernel)
    demoModulesCross = nixpkgs.lib.mapAttrs
      (name: board: [
        board.demoFile
        (mkCrossKernelModule board)
      ])
      boards;

    # Full nixosConfigurations (boot + demo variants)
    nixosConfigurations =
      (mkBoardConfigurations "e52c") //
      (mkBoardConfigurations "rock5a") //
      (mkBoardConfigurations "orangepi5ultra") //
      (mkBoardConfigurations "nanopir6s") //
      (mkBoardConfigurations "nanopir5s") //
      (mkBoardConfigurations "renegade");

    # System-specific packages organized by board
    packages = forAllSystems (system:
      let
        mkImg = board: modules:
          (mkBoardConfiguration board system modules).config.system.build.rockchipImages;
      in {
        # --- E52C ---
        e52c = mkImg "e52c" self.demoModules.e52c;
        e52c-demo = mkImg "e52c" self.demoModules.e52c;
        e52c-boot = mkImg "e52c" self.bootModules.e52c;
        e52c-demo-cross = mkImg "e52c" self.demoModulesCross.e52c;
        e52c-boot-cross = mkImg "e52c" self.bootModulesCross.e52c;

        # --- Rock5A ---
        rock5a = mkImg "rock5a" self.demoModules.rock5a;
        rock5a-demo = mkImg "rock5a" self.demoModules.rock5a;
        rock5a-boot = mkImg "rock5a" self.bootModules.rock5a;
        rock5a-demo-cross = mkImg "rock5a" self.demoModulesCross.rock5a;
        rock5a-boot-cross = mkImg "rock5a" self.bootModulesCross.rock5a;

        # --- Orange Pi 5 Ultra ---
        orangepi5ultra = mkImg "orangepi5ultra" self.demoModules.orangepi5ultra;
        orangepi5ultra-demo = mkImg "orangepi5ultra" self.demoModules.orangepi5ultra;
        orangepi5ultra-boot = mkImg "orangepi5ultra" self.bootModules.orangepi5ultra;
        orangepi5ultra-demo-cross = mkImg "orangepi5ultra" self.demoModulesCross.orangepi5ultra;
        orangepi5ultra-boot-cross = mkImg "orangepi5ultra" self.bootModulesCross.orangepi5ultra;

        # --- NanoPi R6S ---
        nanopir6s = mkImg "nanopir6s" self.demoModules.nanopir6s;
        nanopir6s-demo = mkImg "nanopir6s" self.demoModules.nanopir6s;
        nanopir6s-boot = mkImg "nanopir6s" self.bootModules.nanopir6s;
        nanopir6s-demo-cross = mkImg "nanopir6s" self.demoModulesCross.nanopir6s;
        nanopir6s-boot-cross = mkImg "nanopir6s" self.bootModulesCross.nanopir6s;

        # --- NanoPi R5S ---
        nanopir5s = mkImg "nanopir5s" self.demoModules.nanopir5s; # alias → demo
        nanopir5s-demo = mkImg "nanopir5s" self.demoModules.nanopir5s;
        nanopir5s-boot = mkImg "nanopir5s" self.bootModules.nanopir5s;

        # --- ROC-RK3328-CC Renegade ---
        renegade = mkImg "renegade" self.demoModules.renegade;
        renegade-demo = mkImg "renegade" self.demoModules.renegade;
        renegade-boot = mkImg "renegade" self.bootModules.renegade;
        renegade-demo-cross = mkImg "renegade" self.demoModulesCross.renegade;
        renegade-boot-cross = mkImg "renegade" self.bootModulesCross.renegade;
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
          echo "  e52c-{boot,demo}   # ~6h emulated"
          echo "  rock5a-{boot,demo}"
          echo "  orangepi5ultra-{boot,demo}"
          echo "  nanopir6s-{boot,demo}"
          echo "  renegade-{boot,demo}"
          echo ""
          echo "Cross-compiled builds (fast, x86_64 → aarch64) — nix build .#<board>-<variant>-cross:"
          echo "  e52c-{boot,demo}-cross   # ~1h"
          echo "  rock5a-{boot,demo}-cross"
          echo "  orangepi5ultra-{boot,demo}-cross"
          echo "  nanopir6s-{boot,demo}-cross"
          echo "  nanopir5s-{boot,demo}-cross"
          echo "  renegade-{boot,demo}-cross"
        '';
      };
    });
  };
}
