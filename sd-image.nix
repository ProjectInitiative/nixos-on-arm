{
  config,
  lib,
  pkgs,
  modulesPath,
  ...
}:

with lib;

let
  ubootIdbloaderFile = "${pkgs.uboot-rk3582-generic}/idbloader.img";
  ubootItbFile = "${pkgs.uboot-rk3582-generic}/u-boot.itb";
  bootVolumeLabel = "NIXOS_BOOT";
  rootVolumeLabel = "NIXOS_ROOT";
  efiArch = pkgs.stdenv.hostPlatform.efiArch;

in
{
  imports = [
    (modulesPath + "/profiles/base.nix")
    (modulesPath + "/image/repart.nix")
  ];

  config = {
    # 1. Enable UKI (Unified Kernel Image) Generation.
    boot.loader.systemd-boot.enable = true;
    boot.loader.grub.enable = false;
    boot.loader.generic-extlinux-compatible.enable = false;

    # 2. Configure Kernel and Device Tree.
    boot.kernelPackages = pkgs.linuxPackages_latest;
    hardware.deviceTree = {
      enable = true;
      name = "rockchip/rk3582-radxa-e52c.dtb";
    };

    # 3. Define Kernel Parameters.
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
        pad = file: pkgs.runCommand "${baseNameOf file}-padded" {
          nativeBuildInputs = [ pkgs.coreutils ];
        } ''
          dd if=${file} of=$out bs=512 conv=sync
        '';
      in
      {
        name = "nixos-rockchip-image";
        partitions = {
          # RENAME partitions to force alphabetical order.
          "01-loader1" = {
            repartConfig = {
              Label = "loader1";
              Type = "linux-generic";
              CopyBlocks = (pad ubootIdbloaderFile).outPath;
            };
          };

          "02-loader2" = {
            repartConfig = {
              Label = "loader2";
              Type = "linux-generic";
              CopyBlocks = (pad ubootItbFile).outPath;
            };
          };

          "03-boot" = {
            contents = {
              "/EFI/BOOT/BOOT${lib.toUpper efiArch}.EFI".source = "${pkgs.systemd}/lib/systemd/boot/efi/systemd-boot${efiArch}.efi";

              "/EFI/Linux/${config.system.boot.loader.ukiFile}".source = "${config.system.build.uki}/${config.system.boot.loader.ukiFile}";
            };
            repartConfig = {
              Type = "esp";
              Format = "vfat";
              Label = bootVolumeLabel;
              SizeMinBytes = "256M";
              Bootable = true;
            };
          };

          "04-root" = {
            repartConfig = {
              Type = "root";
              Format = "ext4";
              Label = rootVolumeLabel;
              Minimize = "guess";
            };
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
