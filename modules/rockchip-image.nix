# modules/rockchip-image.nix - Proper NixOS Module
{ config, lib, pkgs, modulesPath, ... }:

with lib;

let
  cfg = config.rockchip;
  
  # Board-specific configurations
  boardConfigs = {
    "rk3582-radxa-e52c" = {
      deviceTree = "rockchip/rk3582-radxa-e52c.dtb";
      defaultUboot = pkgs.uboot-rk3582-generic or null;
      defaultConsole = {
        earlycon = "uart8250,mmio32,0xfeb50000";
        console = "ttyS4,1500000";
      };
    };
  };
  
  # Get board config with fallback
  boardConfig = boardConfigs.${cfg.board} or {
    deviceTree = null;
    defaultUboot = null;
    defaultConsole = {
      earlycon = "earlycon";
      console = "ttyS0,115200";
    };
  };
  
  # Console settings with fallback to board defaults
  consoleSettings = {
    earlycon = cfg.console.earlycon or boardConfig.defaultConsole.earlycon;
    console = cfg.console.console or boardConfig.defaultConsole.console;
  };
  
  # U-Boot package with validation
  ubootPackage = 
    if cfg.uboot.package != null then cfg.uboot.package
    else if boardConfig.defaultUboot != null then boardConfig.defaultUboot
    else throw "No U-Boot package specified for board ${cfg.board}";
  
  # Device tree name with validation
  deviceTreeName = 
    if cfg.deviceTree.name != null then cfg.deviceTree.name
    else if boardConfig.deviceTree != null then boardConfig.deviceTree
    else throw "No device tree specified for board ${cfg.board}";
  
  # Volume labels
  bootVolumeLabel = "NIXOS_BOOT";
  rootVolumeLabel = "NIXOS_ROOT";
  efiArch = pkgs.stdenv.hostPlatform.efiArch;
  
  # Import the monolithic assembler
  assembleMonolithicImage = import ../assemble-monolithic-image.nix;

in
{
  ###### Interface
  options = {
    rockchip = {
      enable = mkEnableOption "Rockchip SoC support";
      
      board = mkOption {
        type = types.str;
        example = "rk3582-radxa-e52c";
        description = "Rockchip board identifier";
      };
      
      uboot = {
        package = mkOption {
          type = types.nullOr types.package;
          default = null;
          description = "U-Boot package to use. If null, will try to use board default.";
        };
      };
      
      deviceTree = {
        name = mkOption {
          type = types.nullOr types.str;
          default = null;
          example = "rockchip/rk3582-radxa-e52c.dtb";
          description = "Device tree blob name. If null, will try to use board default.";
        };
      };
      
      console = {
        earlycon = mkOption {
          type = types.nullOr types.str;
          default = null;
          example = "uart8250,mmio32,0xfeb50000";
          description = "Early console configuration";
        };
        
        console = mkOption {
          type = types.nullOr types.str;
          default = null;
          example = "ttyS4,1500000";
          description = "Main console configuration";
        };
      };
      
      image = {
        buildVariants = {
          full = mkOption {
            type = types.bool;
            default = true;
            description = "Build full eMMC-style image with U-Boot";
          };
          
          sdcard = mkOption {
            type = types.bool;
            default = false;
            description = "Build SD card image without U-Boot";
          };
          
          ubootOnly = mkOption {
            type = types.bool;
            default = false;
            description = "Build U-Boot only image";
          };
        };
        
        bootPartitionStartMB = mkOption {
          type = types.int;
          default = 16;
          description = "Boot partition start offset in MB for full images";
        };
        
        osBootPartitionStartMB = mkOption {
          type = types.int;
          default = 1;
          description = "Boot partition start offset in MB for OS-only images";
        };
      };
    };
  };

  ###### Implementation
  config = mkIf cfg.enable {
    
    # Validate configuration
    assertions = [
      {
        assertion = cfg.board != "";
        message = "rockchip.board must be specified";
      }
      {
        assertion = ubootPackage != null;
        message = "No U-Boot package available for board ${cfg.board}";
      }
      {
        assertion = deviceTreeName != null;
        message = "No device tree specified for board ${cfg.board}";
      }
    ];

    # Import base modules
    imports = [
      (modulesPath + "/profiles/base.nix")
      (modulesPath + "/image/repart.nix")
    ];

    # 1. Boot loader configuration - Use UKI
    boot.loader.systemd-boot.enable = true;
    boot.loader.grub.enable = false;
    boot.loader.generic-extlinux-compatible.enable = false;

    # 2. Kernel and hardware configuration
    boot.kernelPackages = pkgs.linuxPackages_latest;
    hardware.deviceTree = {
      enable = true;
      name = deviceTreeName;
    };

    # 3. Kernel parameters
    boot.kernelParams = [
      "earlycon=${consoleSettings.earlycon}"
      "rootwait"
      "root=/dev/disk/by-label/${rootVolumeLabel}"
      "rw"
      "ignore_loglevel"
      "console=${consoleSettings.console}"
    ];

    # 4. Configure repart for filesystem images
    image.repart = {
      enable = true;
      name = "nixos-rockchip-rootfs";
      
      partitions = {
        # Boot partition with UKI
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
        
        # Root partition with NixOS
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

    # 5. Build Rockchip images
    system.build.rockchipImages = assembleMonolithicImage {
      inherit pkgs lib;
      
      # U-Boot components
      ubootIdbloaderFile = "${ubootPackage}/idbloader.img";
      ubootItbFile = "${ubootPackage}/u-boot.itb";
      
      # Filesystem images from repart
      nixosBootImageFile = "${config.system.build.repart}/10-boot.raw";
      nixosRootfsImageFile = "${config.system.build.repart}/20-root.raw";
      
      # Build variants based on configuration
      buildFullImage = cfg.image.buildVariants.full;
      buildOsImage = cfg.image.buildVariants.sdcard;
      buildUbootImage = cfg.image.buildVariants.ubootOnly;
      
      # Image layout configuration
      bootPartitionStartMB = cfg.image.bootPartitionStartMB;
      osBootPartitionStartMB = cfg.image.osBootPartitionStartMB;
      
      # Partition labels
      bootPartitionLabel = bootVolumeLabel;
      rootPartitionLabel = rootVolumeLabel;
    };

    # 6. Set the primary system image
    system.build.image = mkMerge [
      # If building multiple variants, use the rockchipImages build
      (mkIf (cfg.image.buildVariants.full || cfg.image.buildVariants.sdcard || cfg.image.buildVariants.ubootOnly) 
        config.system.build.rockchipImages)
      
      # If only using repart, keep the repart image as fallback
      (mkIf (!cfg.image.buildVariants.full && !cfg.image.buildVariants.sdcard && !cfg.image.buildVariants.ubootOnly) 
        (mkDefault config.system.build.repart))
    ];

    # 7. Filesystem configuration
    fileSystems = {
      "/" = { 
        device = "/dev/disk/by-label/${rootVolumeLabel}"; 
        fsType = "ext4"; 
      };
      "/boot" = { 
        device = "/dev/disk/by-label/${bootVolumeLabel}"; 
        fsType = "vfat"; 
      };
    };

    # 8. Kernel modules for Rockchip
    boot.initrd.availableKernelModules = [
      "usbhid" "usb_storage" "sd_mod" "mmc_block" "dw_mmc_rockchip"
      "ext4" "vfat" "nls_cp437" "nls_iso8859-1"
      "usbnet" "cdc_ether" "rndis_host"
      # Additional Rockchip-specific modules
      "rockchip_rga" "rockchip_saradc" "rockchip_thermal"
    ];

    # 9. First boot partition resizing
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

    # 10. Hardware and system packages
    hardware.firmware = with pkgs; [ firmwareLinuxNonfree ];
    environment.systemPackages = with pkgs; [
      coreutils
      util-linux
      iproute2
      parted
      cloud-utils
      e2fsprogs
      # Additional useful tools for embedded systems
      usbutils
      pciutils
      htop
    ];

    # 11. Default services for embedded systems
    services.openssh = mkDefault { 
      enable = true; 
      settings.PermitRootLogin = mkDefault "yes"; 
    };
    
    # Enable network manager for easier network setup
    networking.networkmanager.enable = mkDefault true;
    
    # Nix configuration
    nix.settings.experimental-features = mkDefault [ "nix-command" "flakes" ];
  };
}
