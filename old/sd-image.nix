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

in
{
  imports = [
    (modulesPath + "/profiles/base.nix")
    # We are NOT using repart.nix, as we are building the image manually.
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
      "console=ttyS4,1500000"
    ];

    # 4. Define the Disk Image Manually
    # This section replaces `image.repart`. It combines our proven bootloader
    # writing technique with manual partitioning and system population.
    system.build.image = pkgs.runCommand "nixos-rockchip-image.raw" {
      nativeBuildInputs = [
        (pkgs.buildPackages.nix) # Provides nix-store
        pkgs.coreutils           # dd, cp, mkdir, ln, sync, xargs
        pkgs.gptfdisk            # sgdisk
        pkgs.e2fsprogs           # mkfs.ext4
        pkgs.dosfstools          # mkfs.vfat
        pkgs.util-linux          # losetup, mount, umount
      ];

      # Pass necessary files and variables from the Nix evaluation into the build script.
      inherit ubootIdbloaderFile ubootItbFile bootVolumeLabel rootVolumeLabel;
      UKI_FILE = "${config.system.build.uki}/${config.system.boot.loader.ukiFile}";
      SYSTEM_TOPLEVEL = config.system.build.toplevel;

    } ''
      set -ex
      local imageName=$out

      echo "--- Step 1: Creating 4GB raw image file ---"
      dd if=/dev/zero of=$imageName bs=1M count=4096

      echo "--- Step 2: Writing bootloaders to fixed offsets ---"
      dd if=$ubootIdbloaderFile of=$imageName bs=512 seek=64 conv=notrunc
      dd if=$ubootItbFile of=$imageName bs=512 seek=16384 conv=notrunc

      echo "--- Step 3: Creating GPT partition table ---"
      # Partition map from the documentation:
      # boot:   start=32768,  size=229376 sectors -> end=262143
      # rootfs: start=262144, size=- (to the end) -> end=0
      sgdisk --clear $imageName
      sgdisk -n 1:32768:262143  -c 1:"${bootVolumeLabel}" -t 1:ef00 $imageName
      sgdisk -n 2:262144:0       -c 2:"${rootVolumeLabel}" -t 2:8304 $imageName
      sgdisk -A 1:set:2 $imageName # Set ESP bootable attribute

      # --- This is the continuation of the script ---
      echo "--- Step 4: Formatting and Populating Partitions ---"
      # Use a loopback device to treat the image file like a real disk
      loopDevice=$(losetup -f --show -P $imageName)
      
      # Define partition device paths
      local bootPart="''${loopDevice}p1"
      local rootPart="''${loopDevice}p2"

      echo "Formatting $bootPart as vfat and $rootPart as ext4..."
      mkfs.vfat -F 32 -n "${bootVolumeLabel}" "$bootPart"
      mkfs.ext4 -L "${rootVolumeLabel}" -E lazy_itable_init=0,lazy_journal_init=0 "$rootPart"

      echo "Mounting partitions..."
      local rootMnt="/mnt"
      # Mount root first
      mount "$rootPart" "$rootMnt"
      # Then create boot mountpoint inside root and mount boot
      mkdir -p "$rootMnt/boot"
      mount "$bootPart" "$rootMnt/boot"

      echo "Populating root filesystem with NixOS closure..."
      mkdir -p $rootMnt/nix/store
      # Use xargs to avoid "Argument list too long" error on large systems
      nix-store -qR $SYSTEM_TOPLEVEL | xargs cp -at $rootMnt/nix/store

      echo "Creating system profile symlink..."
      mkdir -p "$rootMnt/nix/var/nix/profiles"
      ln -s "$SYSTEM_TOPLEVEL" "$rootMnt/nix/var/nix/profiles/system"

      echo "Copying UKI to boot partition..."
      mkdir -p "$rootMnt/boot/EFI/BOOT"
      cp "$UKI_FILE" "$rootMnt/boot/EFI/BOOT/BOOT${lib.toUpper efiArch}.EFI"

      echo "--- Step 5: Finalizing and Cleaning Up ---"
      sync
      umount -R "$rootMnt"
      losetup -d "$loopDevice"

      echo "NixOS image created successfully at $out"
    '';


    # 5. Define Filesystems and Kernel Modules (unchanged).
    fileSystems."/" = { device = "/dev/disk/by-label/${rootVolumeLabel}"; fsType = "ext4"; };
    fileSystems."/boot" = { device = "/dev/disk/by-label/${bootVolumeLabel}"; fsType = "vfat"; };

    boot.initrd.availableKernelModules = [
      "usbhid" "usb_storage" "sd_mod" "mmc_block" "dw_mmc_rockchip"
      "ext4" "vfat" "nls_cp437" "nls_iso8859-1"
      "usbnet" "cdc_ether" "rndis_host"
    ];

    # 6. Post-boot command to resize the root partition (unchanged).
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

    # 7. Other System Configuration (unchanged).
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
