# nanopi-r5s-boot.nix - Minimal bootable NanoPi R5S configuration
# This module contains ONLY what's needed to boot the hardware
{ config, pkgs, lib, ... }:
{
  imports = [
    ../modules/rockchip-image.nix
  ];

  # Essential kernel modules for NanoPi R5S hardware
  boot.initrd.availableKernelModules = [
    "dw_mmc_rockchip"  # Rockchip SD/eMMC controllers
    "usbnet" "cdc_ether" "rndis_host" # USB networking (for recovery/debug)
    "r8169"  # RTL8125 2.5GbE (uses r8169 driver)
  ];

  # Rockchip board configuration - hardware specific
  rockchip = {
    enable = true;

    # NanoPi R5S specific hardware
    uboot.package = pkgs.ubootNanoPiR5S;
    deviceTree = "rockchip/rk3568-nanopi-r5s.dtb";

    # Console configuration for NanoPi R5S
    # Debug UART2 is on the 12-pin FPC connector
    console = {
      earlycon = "uart8250,mmio32,0xfe660000";
      console = "ttyS2,1500000";
    };

    # Default image variants (can be overridden by consumers)
    image.buildVariants = {
      full = lib.mkDefault true;       # eMMC image with U-Boot
      sdcard = lib.mkDefault true;     # SD card image
      ubootOnly = lib.mkDefault false; # U-Boot only (disabled by default)
    };
  };

  # Essential Nix configuration for flakes
  nix.settings.experimental-features = [ "nix-command" "flakes" ];

  # System version (consumers should override this)
  system.stateVersion = lib.mkDefault "25.11";

  # Ensure console is available
  console.enable = lib.mkDefault true;
}
