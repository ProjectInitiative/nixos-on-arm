# configuration.nix - Fixed and Simplified!
{ config, pkgs, ... }:
{
  imports = [ 
    ./modules/rockchip-image.nix 
  ];
  
  # Platform configuration
  nixpkgs.buildPlatform = "x86_64-linux";
  nixpkgs.hostPlatform = "aarch64-linux";
  
  # Rockchip board configuration
  rockchip = {
    enable = true;
    # board = "rk3582-radxa-e52c";
    
    # U-Boot package - will use board default if not specified
    uboot.package = pkgs.uboot-rk3582-generic;
    
    # Device tree - will use board default if not specified
    deviceTree.name = "rockchip/rk3582-radxa-e52c.dtb";
    
    # Optional: customize console settings (uses board defaults if not specified)
    console = {
      earlycon = "uart8250,mmio32,0xfeb50000";
      console = "ttyS4,1500000";
    };
    
    # Configure which image variants to build
    image.buildVariants = {
      full = true;       # Build full eMMC image with U-Boot (nixos-e52c-full.img)
      sdcard = true;     # Build SD card image without U-Boot (os-only.img)  
      ubootOnly = true;  # Build U-Boot only image
    };
    
  };
  
  # Basic system configuration
  networking.hostName = "nixos-rockchip";
  time.timeZone = "Etc/UTC";
  
  # User accounts
  
  users.users = {
    root = {
      # Set the root password to "root" in plaintext
      initialPassword = "root";
    };
    nixos = {
      isNormalUser = true;
      extraGroups = [ "wheel" ];
      # Set the nixos user password to "nixos" in plaintext
      initialPassword = "nixos";
    };
  };
  
  # System packages
  environment.systemPackages = with pkgs; [
    vim
    git
    htop
    tree
  ];
  
  # SSH access
  services.openssh = {
    enable = true;
    settings.PermitRootLogin = "yes";
  };
  
  # Enable NetworkManager for easier network setup
  networking.networkmanager.enable = true;
  
  # Nix configuration
  nix.settings.experimental-features = [ "nix-command" "flakes" ];
  
  system.stateVersion = "25.11";
}

# Build Instructions:
#
# To build all configured image variants:
#   nix-build -A config.system.build.rockchipImages
#
# To build just the default/primary image:
#   nix-build -A config.system.build.image
#
# Output files will be in result/:
#   - nixos-e52c-full.img  (full eMMC image with U-Boot)
#   - os-only.img          (SD card image without U-Boot)
#   - default.img          (symlink to primary image)
#
# For eMMC flashing, use nixos-e52c-full.img
# For SD card, use os-only.img
#
# Flash with:
#   sudo dd if=result/nixos-e52c-full.img of=/dev/mmcblk0 bs=1M status=progress
#   sudo dd if=result/os-only.img of=/dev/sdb bs=1M status=progress
