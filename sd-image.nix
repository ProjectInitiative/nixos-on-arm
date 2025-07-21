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
  customKernel = pkgs.linuxPackages_latest;
  dtbName = "rk3582-radxa-e52c.dtb";
  dtbPath = "rockchip/${dtbName}";
  bootVolumeLabel = "NIXOS_BOOT";
  rootVolumeLabel = "NIXOS_ROOT";

in
{

  config = {
    image.repart =
      let
        # Helper function to pad files to a 512-byte boundary.
        pad = file: pkgs.runCommand "${baseNameOf file}-padded" { } ''
          cp --no-preserve=mode ${file} $out
          truncate -s %512 $out
        '';
      in
      {
        name = "nixos-rockchip-image";

        partitions = {
          "loader1" = {
            repartConfig = {
              Label = "loader1"; Type = "linux-generic";
              CopyBlocks = (pad ubootIdbloaderFile).outPath;
            };
          };
          "loader2" = {
            repartConfig = {
              Label = "loader2"; Type = "linux-generic";
              CopyBlocks = (pad ubootItbFile).outPath;
            };
          };
          "boot" = {
            repartConfig = {
              Type = "esp"; Format = "vfat"; Label = bootVolumeLabel;
              SizeMinBytes = "256M"; Bootable = true;
            };
            contents."/".source = config.system.build.toplevel + "/boot";
          };
          "root" = {
            repartConfig = {
              Type = "root"; Format = "ext4"; Label = rootVolumeLabel;
              Minimize = "guess";
            };
            storePaths = [ config.system.build.toplevel ];
          };
        };
      };
    
    boot.loader.generic-extlinux-compatible.enable = true;
    boot.loader.grub.enable = false;
    boot.kernelPackages = customKernel;
    hardware.deviceTree = { enable = true; name = dtbPath; };
    boot.kernelParams = [
      "earlycon=uart8250,mmio32,0xfeb50000" "rootwait"
      "root=/dev/disk/by-label/${rootVolumeLabel}" "rw" "ignore_loglevel"
    ];
    fileSystems."/" = { device = "/dev/disk/by-label/${rootVolumeLabel}"; fsType = "ext4"; };
    fileSystems."/boot" = { device = "/dev/disk/by-label/${bootVolumeLabel}"; fsType = "vfat"; };
    boot.initrd.availableKernelModules = [
      "usbhid" "usb_storage" "sd_mod" "mmc_block" "dw_mmc_rockchip" "ext4" "vfat" "nls_cp437" "nls_iso8859-1"
      "usbnet" "cdc_ether" "rndis_host"
    ];
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
    hardware.firmware = with pkgs; [ firmwareLinuxNonfree ];
    environment.systemPackages = with pkgs;
    [
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
