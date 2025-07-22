# assemble-monolithic-image.nix
{ pkgs, lib }:

{ # U-Boot and OS components
  ubootIdbloaderFile
, ubootItbFile
, ukiFile
, systemToplevel

  # Build variant flags
, buildFullImage ? true
, buildOsImage ? false
, buildUbootImage ? false

  # Image layout configuration
, imageName ? "nixos-rockchip-image"
, imageSizeMB ? 4096
, bootOffsetMB ? 16
, bootSizeMB ? 112

  # Bootloader raw offsets (in 512-byte sectors)
, idbloaderOffsetSectors ? 64
, itbOffsetSectors ? 16384
}:

pkgs.stdenv.mkDerivation {
  name = imageName;
  nativeBuildInputs = [
    (pkgs.buildPackages.nix)
    pkgs.coreutils
    pkgs.gptfdisk
    pkgs.e2fsprogs
    pkgs.dosfstools
    pkgs.util-linux
  ];

  # Pass all inputs into the script environment
  inherit
    ubootIdbloaderFile ubootItbFile ukiFile systemToplevel
    imageSizeMB bootOffsetMB bootSizeMB
    idbloaderOffsetSectors itbOffsetSectors;

  buildPhase = ''
    set -euxo pipefail

    # --- Helper: Create and populate a full disk image ---
    function build_full_image {
      local img_name="$1"
      echo "--- Building full image: $img_name ---"

      echo "Creating ${imageSizeMB}MB raw image file..."
      dd if=/dev/zero of="$img_name" bs=1M count=${imageSizeMB} status=progress

      echo "Writing U-Boot binaries to raw offsets..."
      dd if="$ubootIdbloaderFile" of="$img_name" bs=512 seek=$idbloaderOffsetSectors conv=notrunc
      dd if="$ubootItbFile"      of="$img_name" bs=512 seek=$itbOffsetSectors conv=notrunc

      local boot_offset_sectors=$((bootOffsetMB * 1024 * 1024 / 512))
      local boot_size_sectors=$((bootSizeMB * 1024 * 1024 / 512))

      echo "Creating GPT partition table..."
      sgdisk -n 1:$boot_offset_sectors:$(($boot_offset_sectors + $boot_size_sectors)) -c 1:"NIXOS_BOOT" -t 1:ef00 "$img_name"
      sgdisk -n 2:0:0 -c 2:"NIXOS_ROOT" -t 2:8300 "$img_name"

      echo "Formatting and populating partitions..."
      local loopDevice=$(losetup -f --show -P "$img_name")
      mkfs.vfat -F 32 -n "NIXOS_BOOT" "''${loopDevice}p1"
      mkfs.ext4 -L "NIXOS_ROOT" -E lazy_itable_init=0,lazy_journal_init=0 "''${loopDevice}p2"

      local rootMnt="/mnt"
      mount "''${loopDevice}p2" "$rootMnt"
      mkdir -p "$rootMnt/boot"
      mount "''${loopDevice}p1" "$rootMnt/boot"

      mkdir -p "$rootMnt/nix/store"
      nix-store -qR "$systemToplevel" | xargs -r cp -at "$rootMnt/nix/store"
      mkdir -p "$rootMnt/nix/var/nix/profiles"
      ln -s "$systemToplevel" "$rootMnt/nix/var/nix/profiles/system"
      mkdir -p "$rootMnt/boot/EFI/BOOT"
      cp "$ukiFile" "$rootMnt/boot/EFI/BOOT/BOOT${lib.toUpper pkgs.stdenv.hostPlatform.efiArch}.EFI"

      sync
      umount -R "$rootMnt"
      losetup -d "$loopDevice"
    }

    # --- Helper: Create an OS-only image (no bootloaders) ---
    function build_os_image {
        # This function would be similar to build_full_image but would skip the bootloader `dd` steps
        # and would not leave a gap at the beginning of the disk.
        echo "OS-only image build not fully implemented in this example, but would follow similar logic."
    }

    # --- Helper: Create a U-Boot only image ---
    function build_uboot_image {
        local img_name="$1"
        local min_uboot_size_mb=16
        echo "--- Building U-Boot only image: $img_name ---"
        truncate -s ''${min_uboot_size_mb}M "$img_name"
        dd if="$ubootIdbloaderFile" of="$img_name" bs=512 seek=$idbloaderOffsetSectors conv=notrunc
        dd if="$ubootItbFile"      of="$img_name" bs=512 seek=$itbOffsetSectors conv=notrunc
    }

    # --- Main Execution ---
    if [[ "${toString buildFullImage}" == "true" ]]; then
        build_full_image "nixos-rockchip-full.img"
    fi
    if [[ "${toString buildOsImage}" == "true" ]]; then
        # build_os_image "os-only.img" # Call the OS image builder here
        echo "Skipping OS-only image build."
    fi
    if [[ "${toString buildUbootImage}" == "true" ]]; then
        build_uboot_image "uboot-only.img"
    fi
  '';

  installPhase = ''
    mkdir -p $out
    # Copy any images that were built to the output directory
    if [[ -f "nixos-rockchip-full.img" ]]; then cp "nixos-rockchip-full.img" $out/; fi
    if [[ -f "os-only.img" ]]; then cp "os-only.img" $out/; fi
    if [[ -f "uboot-only.img" ]]; then cp "uboot-only.img" $out/; fi
  '';

  dontStrip = true;
  dontFixup = true;
}
