# rockchip-image.nix - Simplified using the monolithic assembler
{
  config,
  lib,
  pkgs,
  modulesPath,
  ...
}:

with lib;

let
  ### Board-Specific Configuration ###
  ubootIdbloaderFile = "${pkgs.uboot-rk3582-generic}/idbloader.img";
  ubootItbFile = "${pkgs.uboot-rk3582-generic}/u-boot.itb";
  bootVolumeLabel = "NIXOS_BOOT";
  rootVolumeLabel = "NIXOS_ROOT";
  efiArch = pkgs.stdenv.hostPlatform.efiArch;

  # Import your monolithic assembler
  assembleMonolithicImage = import ./assemble-monolithic-image.nix;

in
{
  imports = [
    (modulesPath + "/profiles/base.nix")
    (modulesPath + "/image/repart.nix")  # Use repart for filesystem images
  ];

  config = {
    # 1. Enable UKI (Unified Kernel Image) Generation
    boot.loader.systemd-boot.enable = true;
    boot.loader.grub.enable = false;
    boot.loader.generic-extlinux-compatible.enable = false;

    # 2. Configure Kernel and Device Tree
    boot.kernelPackages = pkgs.linuxPackages_latest;
    hardware.deviceTree = {
      enable = true;
      name = "rockchip/rk3582-radxa-e52c.dtb";
    };

    # 3. Define Kernel Parameters
    boot.kernelParams = [
      "earlycon=uart8250,mmio32,0xfeb50000"
      "rootwait"
      "root=/dev/disk/by-label/${rootVolumeLabel}"
      "rw"
      "ignore_loglevel"
      "console=ttyS4,1500000"
    ];

    # 4. Configure repart to create boot and root filesystem images
    image.repart = {
      name = "nixos-rk3582-rootfs";
      
      partitions = {
        # Boot partition - will be populated with UKI
        "10-boot" = {
          contents = {
            "/EFI/BOOT/BOOT${lib.toUpper efiArch}.EFI".source = 
              "${config.system.build.uki}/${config.system.boot.loader.ukiFile}";
          };
          repartConfig = {
            Type = "esp";
            Format = "vfat";
            Label = bootVolumeLabel;
            SizeMinBytes = "100M";
            SizeMaxBytes = "200M";
          };
        };
        
        # Root partition - will be populated with NixOS system
        "20-root" = {
          storePaths = [ config.system.build.toplevel ];
          repartConfig = {
            Type = "root";
            Format = "ext4";
            Label = rootVolumeLabel;
            Minimize = "guess";
          };
        };
      };
    };

    # 5. Create the final monolithic image using our assembler
    system.build.rockchipImage = assembleMonolithicImage {
      inherit pkgs lib;
      
      # U-Boot components
      ubootIdbloaderFile = ubootIdbloaderFile;
      ubootItbFile = ubootItbFile;
      
      # Filesystem images from repart
      nixosBootImageFile = "${config.system.build.image}/10-boot.raw";
      nixosRootfsImageFile = "${config.system.build.image}/20-root.raw";
      
      # Build configuration - create the full monolithic image
      buildFullImage = true;
      buildUbootImage = false;
      buildOsImage = true;  # Also create SD card version
      
      # Rockchip RK3582 specific settings (using defaults mostly)
      bootPartitionStartMB = 16;  # Match your current sector 32768 (16MB)
      imagePaddingMB = 100;       # Some padding for safety
      
      # Custom partition labels to match your setup
      bootPartitionLabel = bootVolumeLabel;
      rootPartitionLabel = rootVolumeLabel;
    };

    # 6. Make the rockchip image the default system image
    system.build.image = config.system.build.rockchipImage;

    # 7. Define Filesystems (same as before)
    fileSystems."/" = { 
      device = "/dev/disk/by-label/${rootVolumeLabel}"; 
      fsType = "ext4"; 
    };
    fileSystems."/boot" = { 
      device = "/dev/disk/by-label/${bootVolumeLabel}"; 
      fsType = "vfat"; 
    };

    # 8. Kernel modules (same as before)
    boot.initrd.availableKernelModules = [
      "usbhid" "usb_storage" "sd_mod" "mmc_block" "dw_mmc_rockchip"
      "ext4" "vfat" "nls_cp437" "nls_iso8859-1"
      "usbnet" "cdc_ether" "rndis_host"
    ];

    # 9. Post-boot partition resizing (same as before)
    boot.postBootCommands = lib.mkBefore ''
      ${pkgs.runtimeShell}/bin/sh -c '
        if [ -f /etc/NIXOS_FIRST_BOOT ]; then
          set -euo pipefail; set -x;
          GROWPART="${pkgs.cloud-utils}/bin/growpart"
          RESIZE2FS="${pkgs.e2fsprogs}/bin/resize2fs"
          FINDMNT="${pkgs.util-linux}/bin/findmnt"
          rootPartDev=$($FINDMNT -n -o SOURCE /)
          rootDevice=$(echo "$rootPartDev" | sed "s/p\?[0-9]*$//")
          partNum=$(echo "$rootPartDev" | sed "s|^$rootDevice||" | sed "s/p//")
          $GROWPART "$rootDevice" "$partNum" && $RESIZE2FS "$rootPartDev"
          rm -f /etc/NIXOS_FIRST_BOOT; sync
        fi
      '
    '';
    environment.etc."NIXOS_FIRST_BOOT".text = "";

    # 10. Other System Configuration (same as before)
    hardware.firmware = with pkgs; [ firmwareLinuxNonfree ];
    environment.systemPackages = with pkgs; [
      coreutils
      util-linux
      iproute2
      parted
      cloud-utils
      e2fsprogs
    ];
    services.openssh = { 
      enable = true; 
      settings.PermitRootLogin = "yes"; 
    };
    nix.settings.experimental-features = [ "nix-command" "flakes" ];
  };
}
