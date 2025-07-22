# image.nix
{ pkgs, lib, config, ... }:

let
  ubootIdbloaderFile = "${pkgs.uboot-rk3582-generic}/idbloader.img";
  ubootItbFile = "${pkgs.uboot-rk3582-generic}/u-boot.itb";
in
{
  imports = [
    ./disko-config.nix
  ];

  config = {
    # == Cross-Compilation Setup ==
    nixpkgs.hostPlatform = "aarch64-linux";
    nixpkgs.buildPlatform = "x86_64-linux";

    # == Disko Configuration (from the documentation) ==
    # This enables building the aarch64 image on an x86_64 host.
    disko.imageBuilder = {
      enableBinfmt = false;
      # Use the build platform's packages for the build VM.
      pkgs = pkgs.buildPackages;
      kernelPackages = pkgs.buildPackages.linuxPackages_latest;
    };

    # == System Configuration for the Target Board ==
    boot.loader.systemd-boot.enable = true;
    boot.loader.grub.enable = false;

    boot.kernelPackages = pkgs.linuxPackages_latest;
    hardware.deviceTree = {
      enable = true;
      name = "rockchip/rk3582-radxa-e52c.dtb";
    };

    boot.kernelParams = [
      "earlycon=uart8250,mmio32,0xfeb50000" "rootwait" "root=/dev/disk/by-label/NIXOS_ROOT"
      "rw" "console=ttyS4,1500000"
    ];

    boot.initrd.availableKernelModules = [
      "usbhid" "usb_storage" "sd_mod" "mmc_block" "dw_mmc_rockchip"
      "ext4" "vfat" "nls_cp437" "nls_iso8859-1"
    ];

    # Your correct partition-growing logic
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

    services.openssh = { enable = true; settings.PermitRootLogin = "yes"; };
    environment.systemPackages = with pkgs; [ cloud-utils e2fsprogs util-linux ];
    hardware.firmware = with pkgs; [ firmwareLinuxNonfree ];

    # == Final Image Build Process ==
    # This is the final attribute you will build.
    system.build.image = pkgs.runCommand "nixos-rockchip-image-final.raw" {
      # We only need `coreutils` for the final `dd` and `cp` steps.
      # It must be from `buildPackages` because it runs on the build machine.
      nativeBuildInputs = [ pkgs.buildPackages.coreutils ];
      inherit ubootIdbloaderFile ubootItbFile;
    } ''
      set -ex

      # Step 1: Copy the base image created by disko.
      # `config.system.build.diskoImages` is a directory containing the raw image.
      # The image is named after the key in `disko.devices.disk`, which is `main`.
      cp ${config.system.build.diskoImages}/main.raw $out

      # Step 2: Inject the bootloaders into the image using our proven `dd` method.
      echo "Injecting bootloaders into generated image..."
      dd if=$ubootIdbloaderFile of=$out bs=512 seek=64 conv=notrunc
      dd if=$ubootItbFile      of=$out bs=512 seek=16384 conv=notrunc

      echo "Final image created successfully."
    '';
  };
}
