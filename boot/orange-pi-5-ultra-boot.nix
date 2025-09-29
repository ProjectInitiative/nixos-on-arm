# orange-pi-5-ultra-boot.nix - Minimal bootable Orange Pi 5 Ultra configuration
# This module contains ONLY what's needed to boot the hardware
{ config, pkgs, lib, ... }:
{
  imports = [ 
    ../modules/rockchip-image.nix 
    ../modules/rknpu.nix
  ];
  
  # Essential kernel modules for Orange Pi 5 Ultra hardware
  boot.initrd.availableKernelModules = [
    "dw_mmc_rockchip"  # Rockchip SD/eMMC controllers
    "usbnet" "cdc_ether" "rndis_host" # USB networking (for recovery/debug)
  ];
  
  # Rockchip board configuration - hardware specific
  rockchip = {
    enable = true;
    
    # Orange Pi 5 Ultra specific hardware
    uboot.package = pkgs.ubootOrangePi5Ultra;
    deviceTree = "rockchip/rk3588-orangepi-5-ultra.dtb";
    
    # Console configuration for Orange Pi 5 Ultra
    console = {
      earlycon = "uart8250,mmio32,0xfeb50000";  # Keep this for very early boot
      console = "tty1";  # Use virtual console (HDMI/framebuffer)
    };
    
    # Default image variants (can be overridden by consumers)
    image.buildVariants = {
      full = lib.mkDefault true;       # eMMC image with U-Boot
      sdcard = lib.mkDefault true;     # SD card image
      ubootOnly = lib.mkDefault false; # U-Boot only (disabled by default)
      spi = lib.mkDefault true;
    };
  };
  
  
  # Essential Nix configuration for flakes
  nix.settings.experimental-features = [ "nix-command" "flakes" ];
  
  # System version (consumers should override this)
  system.stateVersion = lib.mkDefault "25.11";
  
  # Ensure console is available
  console.enable = lib.mkDefault true;
}
