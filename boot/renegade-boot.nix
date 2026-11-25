# renegade-boot.nix - Minimal bootable ROC-RK3328-CC configuration
{ config, pkgs, lib, ... }:
{
  imports = [ 
    ../modules/rockchip-image.nix 
  ];
  
  boot.initrd.availableKernelModules = [
    "dw_mmc_rockchip"
    "usbnet" "cdc_ether" "rndis_host"
  ];
  
  rockchip = {
    enable = true;
    uboot.package = pkgs.ubootRenegade;
    deviceTree = "rockchip/rk3328-roc-cc.dtb";
    
    console = {
      earlycon = "uart8250,mmio32,0xff130000";
      console = "ttyS2,1500000n8";
    };
  };

  # Manually set kernel params
  boot.kernelParams = [
    "console=tty1"
    "console=ttyS2,1500000n8"
    "earlycon=uart8250,mmio32,0xff130000"
  ];

  # NOTE: no usb-enable service here. GPIO1_D2 (line 26 on /dev/gpiochip1) is
  # claimed by the kernel as regulator-vcc-host1-5v, and vcc_host1_5v is
  # enabled by the regulator framework — USB host 5V power is already managed
  # by the kernel, so a userspace gpioset hack just fails with EBUSY.
  nix.settings.experimental-features = [ "nix-command" "flakes" ];
  system.stateVersion = lib.mkDefault "25.11";
}
