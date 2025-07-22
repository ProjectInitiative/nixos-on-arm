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

  # Skip unpack phase since we don't have source to unpack
  dontUnpack = true;

  buildPhase = ''
    set -euxo pipefail

    # --- Helper: Create and populate a full disk image ---
    function build_full_image {
      local img_name="$1"
      echo "--- Building full image: $img_name ---"

      echo "Creating ${toString imageSizeMB}MB raw image file..."
      dd if=/dev/zero of="$img_name" bs=1M count=${toString imageSizeMB} status=progress

      echo "Writing U-Boot binaries to raw offsets..."
      dd if="$ubootIdbloaderFile" of="$img_name" bs=512 seek=${toString idbloaderOffsetSectors} conv=notrunc
      dd if="$ubootItbFile"      of="$img_name" bs=512 seek=${toString itbOffsetSectors} conv=notrunc

      local boot_offset_sectors=$(( ${toString bootOffsetMB} * 1024 * 1024 / 512))
      local boot_size_sectors=$(( ${toString bootSizeMB} * 1024 * 1024 / 512))

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
      local img_name="$1"
      echo "--- Building OS-only image: $img_name ---"

      # Calculate total size needed (boot + estimated root size)
      # For OS-only, we don't need the initial bootloader gap
      local boot_size_sectors=$(( ${toString bootSizeMB} * 1024 * 1024 / 512))
      local estimated_root_size_mb=$((${toString imageSizeMB} - ${toString bootSizeMB}))
      local total_size_mb=$((${toString bootSizeMB} + estimated_root_size_mb))

      echo "Creating ''${total_size_mb}MB OS-only image file..."
      dd if=/dev/zero of="$img_name" bs=1M count=$total_size_mb status=progress

      echo "Creating GPT partition table (starting from sector 2048)..."
      # Start boot partition at sector 2048 (1MB) - standard GPT alignment
      local boot_start_sector=2048
      local boot_end_sector=$((boot_start_sector + boot_size_sectors - 1))
      
      sgdisk -n 1:$boot_start_sector:$boot_end_sector -c 1:"NIXOS_BOOT" -t 1:ef00 "$img_name"
      sgdisk -n 2:0:0 -c 2:"NIXOS_ROOT" -t 2:8300 "$img_name"

      echo "Formatting and populating partitions..."
      local loopDevice=$(losetup -f --show -P "$img_name")
      mkfs.vfat -F 32 -n "NIXOS_BOOT" "''${loopDevice}p1"
      mkfs.ext4 -L "NIXOS_ROOT" -E lazy_itable_init=0,lazy_journal_init=0 "''${loopDevice}p2"

      local rootMnt="/mnt"
      mount "''${loopDevice}p2" "$rootMnt"
      mkdir -p "$rootMnt/boot"
      mount "''${loopDevice}p1" "$rootMnt/boot"

      echo "Populating NixOS system..."
      mkdir -p "$rootMnt/nix/store"
      nix-store -qR "$systemToplevel" | xargs -r cp -at "$rootMnt/nix/store"
      mkdir -p "$rootMnt/nix/var/nix/profiles"
      ln -s "$systemToplevel" "$rootMnt/nix/var/nix/profiles/system"
      mkdir -p "$rootMnt/boot/EFI/BOOT"
      cp "$ukiFile" "$rootMnt/boot/EFI/BOOT/BOOT${lib.toUpper pkgs.stdenv.hostPlatform.efiArch}.EFI"

      sync
      umount -R "$rootMnt"
      losetup -d "$loopDevice"

      echo "OS-only image complete. Note: This image requires external bootloader installation."
    }

    # --- Helper: Create a U-Boot only image ---
    function build_uboot_image {
        local img_name="$1"
        local min_uboot_size_mb=16
        echo "--- Building U-Boot only image: $img_name ---"
        truncate -s ''${min_uboot_size_mb}M "$img_name"
        dd if="$ubootIdbloaderFile" of="$img_name" bs=512 seek=${toString idbloaderOffsetSectors} conv=notrunc
        dd if="$ubootItbFile"      of="$img_name" bs=512 seek=${toString itbOffsetSectors} conv=notrunc
    }

    # --- Main Execution ---
    if [[ "${toString buildFullImage}" == "true" ]]; then
        build_full_image "nixos-rockchip-full.img"
    fi
    if [[ "${toString buildOsImage}" == "true" ]]; then
        build_os_image "nixos-rockchip-os-only.img"
    fi
    if [[ "${toString buildUbootImage}" == "true" ]]; then
        build_uboot_image "uboot-only.img"
    fi
  '';

  installPhase = ''
    mkdir -p $out
    # Copy any images that were built to the output directory
    if [[ -f "nixos-rockchip-full.img" ]]; then cp "nixos-rockchip-full.img" $out/; fi
    if [[ -f "nixos-rockchip-os-only.img" ]]; then cp "nixos-rockchip-os-only.img" $out/; fi
    if [[ -f "uboot-only.img" ]]; then cp "uboot-only.img" $out/; fi
  '';

  dontStrip = true;
  dontFixup = true;
}
