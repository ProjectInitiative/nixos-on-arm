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

  # USB Power Enable for Renegade (GPIO1_D2 = 26)
  systemd.services."usb-enable" = {
    description = "Enable USB Power via GPIO";
    enable = true;
    script = "${pkgs.libgpiod}/bin/gpioset 1 26=1";
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
  };

  nix.settings.experimental-features = [ "nix-command" "flakes" ];
  system.stateVersion = lib.mkDefault "25.11";
}
