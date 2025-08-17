# e52c-boot.nix - Minimal bootable Rock 5A configuration
# This module contains ONLY what's needed to boot the hardware
{ config, pkgs, lib, ... }:
{
  imports = [ 
    ../modules/rockchip-image.nix 
  ];
  
  # Essential kernel modules for Rock 5A hardware
  boot.initrd.availableKernelModules = [
    "dw_mmc_rockchip"  # Rockchip SD/eMMC controllers
    "usbnet" "cdc_ether" "rndis_host" # USB networking (for recovery/debug)
  ];
  
  # Rockchip board configuration - hardware specific
  rockchip = {
    enable = true;
    
    # U-Boot package - will use board default if not specified
    uboot.package = pkgs.uboot-rk3582-generic;
    
    # Device tree - will use board default if not specified
    deviceTree = "rockchip/rk3582-radxa-e52c.dtb";
    
    # Optional: customize console settings (uses board defaults if not specified)
    console = {
      earlycon = "uart8250,mmio32,0xfeb50000";
      console = "ttyS4,1500000";
    };
    
    # Default image variants (can be overridden by consumers)
    image.buildVariants = {
      full = lib.mkDefault true;       # eMMC image with U-Boot
      sdcard = lib.mkDefault true;     # SD card image
      ubootOnly = lib.mkDefault false; # U-Boot only (disabled by default)
    };
  };

  environment.systemPackages = [
    pkgs.git
  ]; 
  
  # Essential Nix configuration for flakes
  nix.settings.experimental-features = [ "nix-command" "flakes" ];
  
  # System version (consumers should override this)
  system.stateVersion = lib.mkDefault "25.11";
  
  # Ensure console is available
  console.enable = lib.mkDefault true;
}
