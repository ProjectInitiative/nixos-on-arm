# e52c-demo.nix - Demo configuration with users, networking, and tools
# This module adds convenience features for testing and development
{ config, pkgs, lib, ... }:
{
  # Import the minimal boot configuration
  imports = [ 
    ../boot/rock5a-boot.nix
  ];
  
  # Override image variants to include U-Boot only for demos
  rockchip.image.buildVariants = {
    full = true;       
    sdcard = true;     
    ubootOnly = true;  # Enable for demo builds
  };
  
  # Minimal system defaults
  networking.hostName = lib.mkDefault "nixos-rock-5a";
  time.timeZone = lib.mkDefault "Etc/UTC";
  
  # Demo user accounts
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
  
  # Development and testing packages
  environment.systemPackages = with pkgs; [
    vim
    git
    htop
    tree
    wget
    curl
  ];
  
  # SSH access for remote testing
  services.openssh = {
    enable = true;
    settings.PermitRootLogin = "yes";
  };
  
  # Enable NetworkManager for easier network setup
  # enP4p65s0 - LAN
  # enP3p49s0 - WAN
  networking = {
    networkmanager = {
        enable = true;
      };
    useDHCP = lib.mkDefault true;
  };
  
  # Allow sudo without password for nixos user (demo only!)
  security.sudo.wheelNeedsPassword = false; 
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
