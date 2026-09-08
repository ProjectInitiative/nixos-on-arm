# nanopi-neo3-plus-demo.nix - Demo configuration for FriendlyElec NanoPi NEO3 Plus
{ config, pkgs, lib, ... }:
{
  imports = [
    ../boot/nanopi-neo3-plus-boot.nix
  ];

  rockchip.image.buildVariants = {
    full = true;
    sdcard = true;
    ubootOnly = true;
  };

  networking.hostName = lib.mkDefault "nixos-nanopineo3plus";
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
