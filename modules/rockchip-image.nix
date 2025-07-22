{ config, lib, pkgs, modulesPath, ... }:

with lib;

let
  cfg = config.rockchip;
  ubootPackage = cfg.uboot.package;
  # Import the fixed assembler module
  assembleMonolithicImage = import ./assemble-monolithic-image.nix;
in
{
  imports = [
    (modulesPath + "/profiles/base.nix")
  ];

  ###### Interface ######
  options = {
    rockchip = {
      enable = mkEnableOption "Rockchip SoC support";
      # You can add board-specific u-boot packages here later if needed
      uboot.package = mkOption {
        type = types.package;
        description = "The U-Boot package providing idbloader.img and u-boot.itb.";
      };
      image = {
        name = mkOption { type = types.str; default = "nixos-rockchip"; };
        imagePaddingMB = mkOption { type = types.int; default = 100; };
        fullImageBootOffsetMB = mkOption { type = types.int; default = 16; };
        osImageBootOffsetMB = mkOption { type = types.int; default = 1; };
        buildVariants = {
          full = mkOption { type = types.bool; default = true; description = "Build full eMMC-style image with U-Boot."; };
          sdcard = mkOption { type = types.bool; default = false; description = "Build OS-only image for SD cards (no U-Boot)."; };
          ubootOnly = mkOption { type = types.bool; default = false; description = "Build a minimal image containing only U-Boot."; };
        };
      };
      # These options are preserved for future use, but not directly used by the UKI boot method
      deviceTree = mkOption { type = types.nullOr types.str; default = null; };
      console = {
        earlycon = mkOption { type = types.nullOr types.str; default = null; };
        console = mkOption { type = types.nullOr types.str; default = null; };
      };
    };
  };

  ###### Implementation ######
  config = mkIf cfg.enable {
    # A. Configure UKI boot. This creates a single EFI file containing the kernel,
    #    initrd, and cmdline, which U-Boot can load directly. It's a modern and
    #    robust way to boot.
    boot.kernelPackages = pkgs.linuxPackages_latest;
    boot.loader.systemd-boot.enable = true;
    boot.loader.grub.enable = false;
    hardware.firmware = with pkgs; [ firmwareLinuxNonfree ];

    hardware.deviceTree = mkIf (cfg.deviceTree != null) {
      enable = true;
      name = cfg.deviceTree;
    };

    # B. Build the boot (VFAT) and root (EXT4) partition images.
    #    These will be the building blocks for the final monolithic image.
    system.build.nixosBootPartitionImage = pkgs.callPackage ./make-fat-fs.nix {
      volumeLabel = "NIXOS_BOOT";
      size = "256M"; # Increased size for safety with future UKIs
      # Populate the VFAT image with the UKI, placing it where U-Boot's UEFI
      # support expects to find the bootloader for arm64.
      populateImageCommands = ''
        mkdir -p ./files/EFI/BOOT
        cp ${config.system.build.uki}/${config.system.boot.loader.ukiFile} ./files/EFI/BOOT/BOOTAA64.EFI
      '';
      storePaths = [ ];
    };

    system.build.nixosRootfsPartitionImage = pkgs.callPackage "${pkgs.path}/nixos/lib/make-ext4-fs.nix" {
      storePaths = [ config.system.build.toplevel ];
      volumeLabel = "NIXOS_ROOT";
      compressImage = false;
    };

    # C. Call the assembler with all required arguments from our config.
    system.build.rockchipImages = assembleMonolithicImage {
      # Pass dependencies
      inherit pkgs lib;

      # Pass U-Boot artifacts
      ubootIdbloaderFile = "${ubootPackage}/idbloader.img";
      ubootItbFile = "${ubootPackage}/u-boot.itb";

      # Pass the generated partition images
      nixosBootImageFile = config.system.build.nixosBootPartitionImage;
      nixosRootfsImageFile = config.system.build.nixosRootfsPartitionImage;

      # Pass configuration from the NixOS module options
      imageName = cfg.image.name;
      imagePaddingMB = cfg.image.imagePaddingMB;
      fullImageBootOffsetMB = cfg.image.fullImageBootOffsetMB;
      osImageBootOffsetMB = cfg.image.osImageBootOffsetMB;

      # Pass the boolean build flags
      buildFullImage = cfg.image.buildVariants.full;
      buildOsImage = cfg.image.buildVariants.sdcard;
      buildUbootImage = cfg.image.buildVariants.ubootOnly;
    };

    # D. Set a convenient default build target (e.g., for `nix build .#nixosConfigurations.my-board.config.system.build.image`)
    system.build.image = config.system.build.rockchipImages;

    # E. Filesystem configuration for the *running* NixOS system.
    #    This must match the labels used when creating the partitions.
    fileSystems = {
      "/" = { device = "/dev/disk/by-label/NIXOS_ROOT"; fsType = "ext4"; };
      "/boot" = { device = "/dev/disk/by-label/NIXOS_BOOT"; fsType = "vfat"; };
    };

    # F. First boot partition resizing.
    #    This script runs on first boot to expand the root partition to fill the disk.
    boot.postBootCommands = lib.mkBefore ''
      # On the first boot, do some maintenance tasks.
      # This script runs in a minimal environment, so we provide full paths to all commands.
      if [ -f /nix-path-registration ]; then
        # Set bash options for safety: exit on error, exit on unset variable, pipefail.
        set -euo pipefail
        # Enable command echoing for debugging.
        set -x

        # --- Define full paths to all our tools upfront for clarity ---
        local FINDMNT="${pkgs.util-linux}/bin/findmnt"
        local LSBLK="${pkgs.util-linux}/bin/lsblk"
        local ECHO="${pkgs.coreutils}/bin/echo"
        local SED="${pkgs.gnused}/bin/sed"
        local SFDISK="${pkgs.util-linux}/bin/sfdisk"
        local GROWPART="${pkgs.cloud-utils}/bin/growpart"
        local PARTPROBE="${pkgs.parted}/bin/partprobe"
        local RESIZE2FS="${pkgs.e2fsprogs}/bin/resize2fs"
        local SLEEP="${pkgs.coreutils}/bin/sleep"
        local RM="${pkgs.coreutils}/bin/rm"
        local SYNC="${pkgs.coreutils}/bin/sync"
        local NIX_STORE="${config.nix.package.out}/bin/nix-store"
        local NIX_ENV="${config.nix.package.out}/bin/nix-env"


        # --- Script Logic ---
        local rootPartDev=$($FINDMNT -n -o SOURCE /)
        local bootDevice=$($LSBLK -npo PKNAME "$rootPartDev")
        # Extract partition number robustly.
        local partNum=$($ECHO "$rootPartDev" | $SED -E 's|^.*[^0-9]([0-9]+)$|\1|')

        $ECHO "Root partition device: ''${rootPartDev}, Boot device: ''${bootDevice}, Root Partition number: ''${partNum}"

        # Attempt to resize the root partition.
        $ECHO "Attempting resize with growpart..."
        # Note: The 'command -v' check is tricky in this environment. We'll just try growpart directly.
        # If cloud-utils is in systemPackages (which it is), growpart should be in the PATH set up for this script.
        # But for max safety, we call it by its full path.
        if $GROWPART "''${bootDevice}" "''${partNum}"; then
            $ECHO "growpart succeeded."
        else
            $ECHO "[WARNING] growpart failed, attempting sfdisk as fallback..."
            $ECHO ",+," | $SFDISK -N"''${partNum}" --no-reread "''${bootDevice}"
        fi

        $ECHO "Running partprobe on ''${bootDevice}..."
        $PARTPROBE "''${bootDevice}" || $ECHO "[WARNING] partprobe on ''${bootDevice} encountered an issue."
        $SLEEP 3 # Give kernel time to recognize changes.

        $ECHO "Resizing filesystem on ''${rootPartDev}..."
        $RESIZE2FS "''${rootPartDev}"

        $ECHO "Registering Nix paths..."
        $NIX_STORE --load-db < /nix-path-registration

        $ECHO "Setting up system profile..."
        $NIX_ENV -p /nix/var/nix/profiles/system --set /run/current-system

        $ECHO "Cleaning up first-boot flag..."
        $RM -f /nix-path-registration
        $SYNC

        $ECHO "First boot setup complete."
        set +x
      fi
    '';


    # G. Ensure necessary packages for the postBootCommands script are in the image.
    environment.systemPackages = with pkgs; [
      coreutils
      util-linux
      iproute2
      parted
      cloud-utils
      e2fsprogs
    ];
  };
}
