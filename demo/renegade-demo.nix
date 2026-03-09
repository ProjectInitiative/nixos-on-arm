# renegade-demo.nix - Demo configuration for ROC-RK3328-CC
{ config, pkgs, lib, ... }:
{
  imports = [ 
    ../boot/renegade-boot.nix
  ];
  
  rockchip.image.buildVariants = {
    full = true;       
    sdcard = true;     
    ubootOnly = true;
  };
  
  networking.hostName = lib.mkDefault "nixos-renegade";
  time.timeZone = lib.mkDefault "Etc/UTC";
  
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
  
  environment.systemPackages = with pkgs; [
    vim
    git
    htop
    tree
    wget
    curl
    libgpiod
  ];
  
  services.openssh = {
    enable = true;
    settings.PermitRootLogin = "yes";
  };
  
  networking = {
    networkmanager.enable = true;
    useDHCP = lib.mkDefault true;
  };
  
  security.sudo.wheelNeedsPassword = false;
}
