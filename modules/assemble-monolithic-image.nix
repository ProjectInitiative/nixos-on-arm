# assemble-monolithic-image.nix - Fixed Version
{ pkgs
, lib
, ubootIdbloaderFile
, ubootItbFile
, nixosBootImageFile
, nixosRootfsImageFile
# Image type selection
, buildFullImage ? true
, buildUbootImage ? false
, buildOsImage ? false
# Rockchip-specific defaults
, idbloaderOffsetSectors ? 64      # 32 KiB - standard for most Rockchip SoCs
, itbOffsetSectors ? 16384          # 8 MiB - standard for most Rockchip SoCs
, bootPartitionStartMB ? 16         # 16MB for full image (eMMC style)
, osBootPartitionStartMB ? 1        # 1MB for OS-only (SD card style)
, alignmentMB ? 1                   # 1MB alignment
, imagePaddingMB ? 100              # Extra padding for safety
, minUbootImageMB ? 16              # Minimum U-Boot image size
# Partition configuration
, bootPartitionLabel ? "NIXOS_BOOT"
, rootPartitionLabel ? "NIXOS_ROOT"
, useCustomUUIDs ? false
, bootPartitionUUID ? null
, rootPartitionUUID ? null
}:

let
  inherit (lib) optionalString;
  
  # Convert MB to bytes/sectors with validation
  mbToBytes = mb: mb * 1024 * 1024;
  mbToSectors = mb: (mbToBytes mb) / 512;
  
  # Validate inputs
  validateInputs = 
    assert lib.assertMsg (idbloaderOffsetSectors > 0) "idbloaderOffsetSectors must be > 0";
    assert lib.assertMsg (itbOffsetSectors > idbloaderOffsetSectors) "itbOffsetSectors must be > idbloaderOffsetSectors";
    assert lib.assertMsg (bootPartitionStartMB >= 1) "bootPartitionStartMB must be >= 1";
    assert lib.assertMsg (alignmentMB >= 1) "alignmentMB must be >= 1";
    true;

  # Standard GUID types
  guidTypes = {
    linux = "0FC63DAF-8483-4772-8E79-3D69D8477DE4";
    efi = "C12A7328-F81F-11D2-BA4B-00A0C93EC93B";
  };

  # Image configurations
  configs = {
    full = {
      name = "nixos-e52c-full.img";
      bootStartSectors = mbToSectors bootPartitionStartMB;
      includeUboot = true;
    };
    os = {
      name = "os-only.img";
      bootStartSectors = mbToSectors osBootPartitionStartMB;
      includeUboot = false;
    };
    uboot = {
      name = "uboot-only.img";
      includeUboot = true;
      ubootOnly = true;
    };
  };

in
assert validateInputs;

pkgs.stdenv.mkDerivation {
  name = "rockchip-disk-images";

  # Only include sources that actually exist and are needed
  buildInputs = lib.filter (f: f != null) [
    ubootIdbloaderFile
    ubootItbFile
  ] ++ lib.optionals (buildOsImage || buildFullImage) [
    nixosBootImageFile
    nixosRootfsImageFile
  ];

  nativeBuildInputs = with pkgs; [
    coreutils
    util-linux
    parted
    gawk
    e2fsprogs  # For filesystem tools
  ];

  # Create build script
  buildPhase = ''
    set -euo pipefail
    
    echo "=== Rockchip Image Builder ==="
    echo "Build variants requested:"
    echo "  Full image: ${if buildFullImage then "yes" else "no"}"
    echo "  OS image: ${if buildOsImage then "yes" else "no"}"
    echo "  U-Boot only: ${if buildUbootImage then "yes" else "no"}"
    echo ""
    
    # Input validation and setup
    validate_inputs() {
      local missing_files=()
      
      ${optionalString (buildUbootImage || buildFullImage) ''
        if [[ ! -f "${ubootIdbloaderFile}" ]]; then
          missing_files+=("idbloader: ${ubootIdbloaderFile}")
        fi
        if [[ ! -f "${ubootItbFile}" ]]; then
          missing_files+=("u-boot ITB: ${ubootItbFile}")
        fi
      ''}
      
      ${optionalString (buildOsImage || buildFullImage) ''
        if [[ ! -f "${nixosBootImageFile}" ]]; then
          missing_files+=("boot image: ${nixosBootImageFile}")
        fi
        if [[ ! -f "${nixosRootfsImageFile}" ]]; then
          missing_files+=("rootfs image: ${nixosRootfsImageFile}")
        fi
      ''}
      
      if [[ ''${#missing_files[@]} -gt 0 ]]; then
        echo "Error: Missing required files:"
        printf '  %s\n' "''${missing_files[@]}"
        exit 1
      fi
      
      echo "All required input files found"
    }
    
    # Get file sizes
    get_file_info() {
      boot_img_sectors=0
      rootfs_img_sectors=0
      rootfs_img_bytes=0
      
      ${optionalString (buildOsImage || buildFullImage) ''
        if [[ -f "${nixosBootImageFile}" ]]; then
          local boot_bytes=$(stat -c%s "${nixosBootImageFile}")
          boot_img_sectors=$(( (boot_bytes + 511) / 512 ))
          echo "Boot image: $boot_bytes bytes ($boot_img_sectors sectors)"
        fi
        
        if [[ -f "${nixosRootfsImageFile}" ]]; then
          rootfs_img_bytes=$(stat -c%s "${nixosRootfsImageFile}")
          rootfs_img_sectors=$(( (rootfs_img_bytes + 511) / 512 ))
          echo "Root image: $rootfs_img_bytes bytes ($rootfs_img_sectors sectors)"
        fi
      ''}
    }
    
    # Image size calculators
    calculate_uboot_image_size() {
      local itb_bytes=$(stat -c%s "${ubootItbFile}")
      local itb_end=$((${toString itbOffsetSectors} * 512 + itb_bytes))
      local aligned=$((((itb_end + ${toString (mbToBytes alignmentMB)} - 1) / ${toString (mbToBytes alignmentMB)}) * ${toString (mbToBytes alignmentMB)}))
      local min_size=${toString (mbToBytes minUbootImageMB)}
      echo $((aligned > min_size ? aligned : min_size))
    }
    
    calculate_image_size() {
      local boot_start=$1
      local rootfs_start=$2
      local min_end=$((rootfs_start * 512 + rootfs_img_bytes))
      local padded=$((min_end + ${toString (mbToBytes imagePaddingMB)}))
      echo $((((padded + ${toString (mbToBytes alignmentMB)} - 1) / ${toString (mbToBytes alignmentMB)}) * ${toString (mbToBytes alignmentMB)}))
    }
    
    # GPT table creation
    create_gpt_table() {
      local img_name=$1
      local boot_start=$2
      local boot_size=$3  
      local root_start=$4
      local root_size=$5
      
      echo "Creating GPT table for $img_name"
      echo "  Boot: sector $boot_start, size $boot_size"
      echo "  Root: sector $root_start, size $root_size"
      
      # Create partition table with sfdisk
      sfdisk "$img_name" << EOF
    label: gpt
    unit: sectors
    first-lba: 34
    
    name="${bootPartitionLabel}", start=$boot_start, size=$boot_size, type=${guidTypes.efi}
    name="${rootPartitionLabel}", start=$root_start, size=$root_size, type=${guidTypes.linux}
    EOF
      
      echo "Verifying partition table..."
      sfdisk --verify "$img_name" || {
        echo "Warning: Partition verification issues detected"
        sfdisk --list "$img_name"
      }
    }
    
    # Build U-Boot only image
    ${optionalString buildUbootImage ''
      build_uboot_image() {
        local img_name="${configs.uboot.name}"
        echo ""
        echo "=== Building $img_name ==="
        
        local img_size=$(calculate_uboot_image_size)
        echo "Creating U-Boot image: $img_size bytes"
        
        truncate -s "$img_size" "$img_name"
        
        echo "Writing idbloader at sector ${toString idbloaderOffsetSectors}"
        dd if="${ubootIdbloaderFile}" of="$img_name" \
           seek=${toString idbloaderOffsetSectors} conv=notrunc,fsync bs=512 status=progress
           
        echo "Writing ITB at sector ${toString itbOffsetSectors}"
        dd if="${ubootItbFile}" of="$img_name" \
           seek=${toString itbOffsetSectors} conv=notrunc,fsync bs=512 status=progress
           
        echo "=== $img_name completed ==="
      }
    ''}
    
    # Build OS image (SD card style)
    ${optionalString buildOsImage ''
      build_os_image() {
        local img_name="${configs.os.name}"
        echo ""
        echo "=== Building $img_name ==="
        
        local boot_start=${toString configs.os.bootStartSectors}
        local rootfs_start=$((boot_start + boot_img_sectors))
        local img_size=$(calculate_image_size $boot_start $rootfs_start)
        
        echo "Image layout:"
        echo "  Boot partition: sector $boot_start ($boot_img_sectors sectors)"
        echo "  Root partition: sector $rootfs_start ($rootfs_img_sectors sectors)"
        echo "  Total size: $img_size bytes"
        
        truncate -s "$img_size" "$img_name"
        
        create_gpt_table "$img_name" $boot_start $boot_img_sectors $rootfs_start $rootfs_img_sectors
        
        echo "Writing filesystem images..."
        dd if="${nixosBootImageFile}" of="$img_name" \
           seek=$boot_start conv=notrunc,fsync bs=512 status=progress
        dd if="${nixosRootfsImageFile}" of="$img_name" \
           seek=$rootfs_start conv=notrunc,fsync bs=512 status=progress
           
        echo "=== $img_name completed ==="
      }
    ''}
    
    # Build full image (eMMC style with U-Boot)
    ${optionalString buildFullImage ''
      build_full_image() {
        local img_name="${configs.full.name}"
        echo ""
        echo "=== Building $img_name ==="
        
        local boot_start=${toString configs.full.bootStartSectors}
        local rootfs_start=$((boot_start + boot_img_sectors))
        local img_size=$(calculate_image_size $boot_start $rootfs_start)
        
        echo "Image layout:"
        echo "  U-Boot idbloader: sector ${toString idbloaderOffsetSectors}"
        echo "  U-Boot ITB: sector ${toString itbOffsetSectors}"
        echo "  Boot partition: sector $boot_start ($boot_img_sectors sectors)"
        echo "  Root partition: sector $rootfs_start ($rootfs_img_sectors sectors)"
        echo "  Total size: $img_size bytes"
        
        truncate -s "$img_size" "$img_name"
        
        echo "Writing U-Boot components..."
        dd if="${ubootIdbloaderFile}" of="$img_name" \
           seek=${toString idbloaderOffsetSectors} conv=notrunc,fsync bs=512 status=progress
        dd if="${ubootItbFile}" of="$img_name" \
           seek=${toString itbOffsetSectors} conv=notrunc,fsync bs=512 status=progress
        
        create_gpt_table "$img_name" $boot_start $boot_img_sectors $rootfs_start $rootfs_img_sectors
        
        echo "Writing filesystem images..."
        dd if="${nixosBootImageFile}" of="$img_name" \
           seek=$boot_start conv=notrunc,fsync bs=512 status=progress
        dd if="${nixosRootfsImageFile}" of="$img_name" \
           seek=$rootfs_start conv=notrunc,fsync bs=512 status=progress
           
        echo "=== $img_name completed ==="
      }
    ''}
    
    # Main execution
    main() {
      validate_inputs
      get_file_info
      
      ${optionalString buildUbootImage "build_uboot_image"}
      ${optionalString buildOsImage "build_os_image"}
      ${optionalString buildFullImage "build_full_image"}
      
      echo ""
      echo "=== All requested images built successfully ==="
    }
    
    main
  '';

  installPhase = ''
    mkdir -p $out
    
    ${optionalString buildUbootImage ''
      if [[ -f "${configs.uboot.name}" ]]; then
        cp "${configs.uboot.name}" $out/
        echo "Installed ${configs.uboot.name}"
      fi
    ''}
    
    ${optionalString buildOsImage ''
      if [[ -f "${configs.os.name}" ]]; then
        cp "${configs.os.name}" $out/
        echo "Installed ${configs.os.name}"
      fi
    ''}
    
    ${optionalString buildFullImage ''
      if [[ -f "${configs.full.name}" ]]; then
        cp "${configs.full.name}" $out/
        echo "Installed ${configs.full.name}"
      fi
    ''}
    
    # Create default symlink to the primary image
    ${optionalString buildFullImage ''
      ln -sf "${configs.full.name}" $out/default.img
      echo "Created default.img -> ${configs.full.name}"
    ''}
    ${optionalString (!buildFullImage && buildOsImage) ''
      ln -sf "${configs.os.name}" $out/default.img
      echo "Created default.img -> ${configs.os.name}"
    ''}
    ${optionalString (!buildFullImage && !buildOsImage && buildUbootImage) ''
      ln -sf "${configs.uboot.name}" $out/default.img
      echo "Created default.img -> ${configs.uboot.name}"
    ''}
    
    echo "Installation completed successfully to $out"
    echo "Contents:"
    ls -la $out/
  '';

  dontStrip = true;
  dontFixup = true;
}
