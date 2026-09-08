# nanopi-neo3-plus-boot.nix - Minimal bootable FriendlyElec NanoPi NEO3 Plus configuration
{ config, pkgs, lib, ... }:
{
  imports = [
    ../modules/rockchip-image.nix
  ];

  # SD (dw_mmc_rockchip) and eMMC (sdhci_of_dwcmshc) drivers are built-in
  # (=y in the arm64 defconfig), but listing them here is harmless and
  # documents intent. The GbE (stmmac/dwmac-rk) drivers are modules.
  boot.initrd.availableKernelModules = [
    "dw_mmc_rockchip"
    "sdhci_of_dwcmshc"
    "stmmac" "stmmac_platform" "dwmac_rk"
  ];

  rockchip = {
    enable = true;
    uboot.package = pkgs.ubootNanopiNeo3Plus;
    deviceTree = "rockchip/rk3528-nanopi-neo3-plus.dtb";

    console = {
      earlycon = "uart8250,mmio32,0xff9f0000";
      console = "ttyS0,1500000n8";
    };
  };

  # Manually set kernel params
  # Debug UART is UART0_M0 @ 0xff9f0000, 1500000 8n1 (3-pin header)
  boot.kernelParams = [
    "console=tty1"
    "console=ttyS0,1500000n8"
    "earlycon=uart8250,mmio32,0xff9f0000"
  ];

  nix.settings.experimental-features = [ "nix-command" "flakes" ];
  system.stateVersion = lib.mkDefault "25.11";
}
