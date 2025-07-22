# modules/rockchip-image.nix - Final Manual Build Version
{ config, lib, pkgs, modulesPath, ... }:

with lib;

let
  cfg = config.rockchip;
  ubootPackage = cfg.uboot.package;
  # Import the monolithic assembler, which will now build the entire image
  assembleMonolithicImage = import ./assemble-monolithic-image.nix { inherit pkgs lib; };
in
{
  # REMOVED: No longer importing repart.nix
  imports = [
    (modulesPath + "/profiles/base.nix")
  ];

  ###### Interface ######
  options = {
    rockchip = {
      enable = mkEnableOption "Rockchip SoC support";
      board = mkOption { type = types.str; default = "rk3582-radxa-e52c"; };
      uboot.package = mkOption { type = types.package; };
      image = {
        name = mkOption { type = types.str; default = "nixos-rockchip"; };
        sizeMB = mkOption { type = types.int; default = 4096; };
        bootOffsetMB = mkOption { type = types.int; default = 16; };
        bootSizeMB = mkOption { type = types.int; default = 112; };
        buildVariants = {
          full = mkOption { type = types.bool; default = true; };
          sdcard = mkOption { type = types.bool; default = false; };
          ubootOnly = mkOption { type = types.bool; default = false; };
        };
      };
      # Other options like deviceTree and console are kept for consistency but not used in this build method
      deviceTree = { name = mkOption { type = types.nullOr types.str; default = null; }; };
      console = {
        earlycon = mkOption { type = types.nullOr types.str; default = null; };
        console = mkOption { type = types.nullOr types.str; default = null; };
      };
    };
  };

  ###### Implementation ######
  config = mkIf cfg.enable {
    # 1. Boot loader configuration - Use UKI
    boot.kernelPackages = pkgs.linuxPackages_latest;
    boot.loader.systemd-boot.enable = true;
    boot.loader.grub.enable = false;

    # 2. Define the image build process using the robust assembler
    system.build.rockchipImages = assembleMonolithicImage {
      # Pass U-Boot and OS components
      ubootIdbloaderFile = "${ubootPackage}/idbloader.img";
      ubootItbFile = "${ubootPackage}/u-boot.itb";
      ukiFile = "${config.system.build.uki}/${config.system.boot.loader.ukiFile}";
      systemToplevel = config.system.build.toplevel;

      # Pass image layout configuration
      imageName = cfg.image.name;
      imageSizeMB = cfg.image.sizeMB;
      bootOffsetMB = cfg.image.bootOffsetMB;
      bootSizeMB = cfg.image.bootSizeMB;

      # Pass build variant flags
      buildFullImage = cfg.image.buildVariants.full;
      buildOsImage = cfg.image.buildVariants.sdcard;
      buildUbootImage = cfg.image.buildVariants.ubootOnly;
    };

    # 3. Set a convenient default build target
    system.build.image = config.system.build.rockchipImages;

    # 4. Filesystem configuration for the running NixOS system
    fileSystems = {
      "/" = { device = "/dev/disk/by-label/NIXOS_ROOT"; fsType = "ext4"; };
      "/boot" = { device = "/dev/disk/by-label/NIXOS_BOOT"; fsType = "vfat"; };
    };

    # 5. First boot partition resizing (preserved from your original file)
    boot.postBootCommands = lib.mkBefore ''
      ${pkgs.runtimeShell}/bin/sh -c '
        if [ -f /etc/NIXOS_FIRST_BOOT ]; then
          set -euo pipefail; set -x;
          GROWPART="${pkgs.cloud-utils}/bin/growpart"
          RESIZE2FS="${pkgs.e2fsprogs}/bin/resize2fs"
          FINDMNT="${pkgs.util-linux}/bin/findmnt"
          
          echo "First boot detected, expanding root partition..."
          rootPartDev=$($FINDMNT -n -o SOURCE /)
          rootDevice=$(echo "$rootPartDev" | sed "s/p\?[0-9]*$//")
          partNum=$(echo "$rootPartDev" | sed "s|^$rootDevice||" | sed "s/p//")
         
          if $GROWPART "$rootDevice" "$partNum"; then
            echo "Partition expanded, resizing filesystem..."
            $RESIZE2FS "$rootPartDev"
          else
            echo "Partition expansion failed or not needed"
          fi
          
          rm -f /etc/NIXOS_FIRST_BOOT
          sync
          echo "First boot setup completed"
        fi
      '
    '';
    environment.etc."NIXOS_FIRST_BOOT".text = "";

    # 6. Ensure necessary packages are available in the final image
    environment.systemPackages = with pkgs; [
      cloud-utils
      e2fsprogs
      util-linux # For findmnt
    ];
  };
}
