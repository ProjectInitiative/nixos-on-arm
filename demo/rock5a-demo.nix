# rock5a-demo.nix - Demo configuration with users, networking, and tools
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
      initialPassword = "root";
    };
    nixos = {
      isNormalUser = true;
      extraGroups = [ "wheel" ];
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
  
  # NetworkManager for easy network setup during testing
  networking = {
    networkmanager.enable = true;
    useDHCP = lib.mkDefault true;
  };
  
  # Allow sudo without password for nixos user (demo only!)
  security.sudo.wheelNeedsPassword = false;
}
