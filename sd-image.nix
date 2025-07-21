{
  config,
  lib,
  pkgs,
  modulesPath,
  ...
}:

with lib;

let
  # Define variables for bootloader files and volume labels for clarity.
  ubootIdbloaderFile = "${pkgs.uboot-rk3582-generic}/idbloader.img";
  ubootItbFile = "${pkgs.uboot-rk3582-generic}/u-boot.itb";
  bootVolumeLabel = "NIXOS_BOOT";
  rootVolumeLabel = "NIXOS_ROOT";

in
{
  imports = [
    # Import standard NixOS profiles.
    (modulesPath + "/profiles/base.nix")
    # Import the repart module for creating the disk image.
    (modulesPath + "/image/repart.nix")
  ];

  config = {
    # 1. Enable UKI (Unified Kernel Image) Generation.
    #    We enable systemd-boot not to use it as the loader, but because
    #    it's the mechanism that triggers NixOS to build a UKI.
    boot.loader.systemd-boot.enable = true;
    boot.loader.grub.enable = false; # Ensure GRUB is disabled.
    boot.loader.generic-extlinux-compatible.enable = false; # Not needed for UKI.

    # 2. Configure Kernel and Device Tree.
    #    The UKI build process will automatically bundle these.
    boot.kernelPackages = pkgs.linuxPackages_latest;
    hardware.deviceTree = {
      enable = true;
      name = "rockchip/rk3582-radxa-e52c.dtb";
    };

    # 3. Define Kernel Parameters.
    #    These will be embedded directly into the UKI.
    boot.kernelParams = [
      "earlycon=uart8250,mmio32,0xfeb50000"
      "rootwait"
      "root=/dev/disk/by-label/${rootVolumeLabel}"
      "rw"
      "ignore_loglevel"
    ];

    # 4. Define the Disk Image Layout using Repart.
    image.repart =
      let
        # Helper function to pad files to a 512-byte boundary for raw block copying.
        pad = file: pkgs.runCommand "${baseNameOf file}-padded" { } ''
          cp --no-preserve=mode ${file} $out
          truncate -s %512 $out
        '';
      in
      {
        name = "nixos-rockchip-image";
        partitions = {
          # Partition for the first-stage U-Boot bootloader (IDB).
          "loader1" = {
            repartConfig = {
              Label = "loader1";
              Type = "linux-generic";
              CopyBlocks = (pad ubootIdbloaderFile).outPath;
            };
          };

          # Partition for the second-stage U-Boot bootloader (ITB).
          "loader2" = {
            repartConfig = {
              Label = "loader2";
              Type = "linux-generic";
              CopyBlocks = (pad ubootItbFile).outPath;
            };
          };

          # The boot partition (ESP), which will hold our single UKI file.
          "boot" = {
            contents = {
              # This is the standard UEFI path that U-Boot will look for.
              # 'BOOTAA64.EFI' is the conventional name for ARM64 EFI applications.
              "/EFI/BOOT/BOOTAA64.EFI".source =
                "${config.system.build.uki}/${config.system.boot.loader.ukiFile}";
            };
            repartConfig = {
              Type = "esp";
              Format = "vfat";
              Label = bootVolumeLabel;
              SizeMinBytes = "256M";
              Bootable = true; # Mark this partition as bootable.
            };
          };

          # The main root filesystem partition.
          "root" = {
            repartConfig = {
              Type = "root";
              Format = "ext4";
              Label = rootVolumeLabel;
              Minimize = "guess"; # Automatically shrink to a minimal size.
            };
            # Include the entire NixOS system closure in this partition.
            storePaths = [ config.system.build.toplevel ];
          };
        };
      };

    # 5. Define Filesystems and Kernel Modules.
    fileSystems."/" = { device = "/dev/disk/by-label/${rootVolumeLabel}"; fsType = "ext4"; };
    fileSystems."/boot" = { device = "/dev/disk/by-label/${bootVolumeLabel}"; fsType = "vfat"; };

    boot.initrd.availableKernelModules = [
      "usbhid" "usb_storage" "sd_mod" "mmc_block" "dw_mmc_rockchip"
      "ext4" "vfat" "nls_cp437" "nls_iso8859-1"
      "usbnet" "cdc_ether" "rndis_host"
    ];

    # 6. Post-boot command to resize the root partition on first boot.
    boot.postBootCommands = lib.mkBefore ''
      if [ -f /nix-path-registration ]; then
        set -euo pipefail; set -x;
        local GROWPART="${pkgs.cloud-utils}/bin/growpart"
        local RESIZE2FS="${pkgs.e2fsprogs}/bin/resize2fs"
        local FINDMNT="${pkgs.util-linux}/bin/findmnt"
        local rootPartDev=$($FINDMNT -n -o SOURCE /)
        local bootDevice=$($FINDMNT -n -o SOURCE / | sed 's/[0-9]*$//')
        local partNum=$(echo "$rootPartDev" | sed 's|^.*[^0-9]||')
        $GROWPART "$bootDevice" "$partNum" && $RESIZE2FS "$rootPartDev"
        rm -f /nix-path-registration; sync
      fi
    '';

    # 7. Other System Configuration.
    hardware.firmware = with pkgs; [ firmwareLinuxNonfree ];
    environment.systemPackages = with pkgs; [
      coreutils
      util-linux
      iproute2
      parted
      cloud-utils
      e2fsprogs
    ];
    services.openssh = { enable = true; settings.PermitRootLogin = "yes"; };
    nix.settings.experimental-features = [ "nix-command" "flakes" ];
  };
}
