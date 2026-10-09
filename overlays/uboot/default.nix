final: prev: {
  # U-Boot >= 2026.07 mainlined RK3582 support (rk3588.c ft_system_setup +
  # CONFIG_OF_SYSTEM_SETUP in generic-rk3588_defconfig), so our local patches
  # 0001/0002 are now redundant and fail to apply. Kept in patches/ for
  # reference until the pin moves past 2026.07.
  uboot-rk3582-generic = prev.buildUBoot {
    pname = "uboot-rk3582-generic";
    defconfig = "generic-rk3588_defconfig";

    extraMeta.platforms = [ "aarch64-linux" ];
    # 2026.07 binman ignores env-attr blobs; pass as make vars (see NEO3 Plus note).
    extraMakeFlags = [
      "BL31=${prev.armTrustedFirmwareRK3588}/bl31.elf"
      "ROCKCHIP_TPL=${prev.rkbin.TPL_RK3588}"
    ];
    filesToInstall = [
      "u-boot.itb"
      "idbloader.img"
      "u-boot-rockchip.bin"
    ];
    
    extraMeta = {
      description = "Patched U-Boot for generic RK3582/RK3588 boards";
    };
  };

  ubootRock5ModelA = prev.buildUBoot {
    defconfig = "rock5a-rk3588s_defconfig";
    extraMeta.platforms = [ "aarch64-linux" ];
    extraMakeFlags = [
      "BL31=${prev.armTrustedFirmwareRK3588}/bl31.elf"
      "ROCKCHIP_TPL=${prev.rkbin.TPL_RK3588}"
    ];
    filesToInstall = [
      "u-boot.itb"
      "idbloader.img"
      "u-boot-rockchip.bin"
    ];
  };

  ubootOrangePi5Ultra = prev.buildUBoot {
    version = "v2025.10-rc5";
    src = prev.fetchFromGitHub {
      owner = "u-boot";
      repo = "u-boot";
      rev = "v2025.10-rc5";
      hash = "sha256-EJOS0wRIRBexyX2d0GyIWpGIpB3+fUeXiHZvhEfrhYA=";
    };
    defconfig = "orangepi-5-ultra-rk3588_defconfig";
    extraMeta.platforms = [ "aarch64-linux" ];
    extraMakeFlags = [
      "BL31=${prev.armTrustedFirmwareRK3588}/bl31.elf"
      "ROCKCHIP_TPL=${prev.rkbin.TPL_RK3588}"
    ];
    filesToInstall = [
      "u-boot.itb"
      "idbloader.img"
      "u-boot-rockchip.bin"
      "u-boot-rockchip-spi.bin"
    ];
  };

  ubootNanopiR6S = prev.buildUBoot {
    defconfig = "nanopi-r6s-rk3588s_defconfig";
    extraMeta.platforms = [ "aarch64-linux" ];
    extraMakeFlags = [
      "BL31=${prev.armTrustedFirmwareRK3588}/bl31.elf"
      "ROCKCHIP_TPL=${prev.rkbin.TPL_RK3588}"
    ];
    filesToInstall = [
      "u-boot.itb"
      "idbloader.img"
      "u-boot-rockchip.bin"
    ];
  };

  ubootRenegade = prev.buildUBoot {
    defconfig = "roc-cc-rk3328_defconfig";
    extraMeta.platforms = [ "aarch64-linux" ];
    extraMakeFlags = [
      "BL31=${prev.armTrustedFirmwareRK3328}/bl31.elf"
    ];
    filesToInstall = [
      "u-boot.itb"
      "idbloader.img"
      "u-boot-rockchip.bin"
    ];
  };

  # NanoPi NEO3 Plus is RK3528A. Upstream U-Boot (2026.04, the nixpkgs
  # default) ships generic-rk3528_defconfig, whose board DT matches the
  # NEO3 Plus debug UART (UART0_M0 @ 1500000n8) and enables eMMC + SD.
  # BL31/TPL are vendor blobs from rockchip-linux/rkbin (no mainline TF-A
  # for RK3528 yet). nixpkgs' rkbin passthru has no RK3528 attributes, so
  # the blob paths are referenced directly.
  # NOTE: blobs must be passed via extraMakeFlags (command-line make vars).
  # Passing them as derivation env attrs (BL31/ROCKCHIP_TPL) is unreliable:
  # binman then sees empty -a paths (env vars are not always imported as
  # make variables inside the sandboxed build).
  ubootNanopiNeo3Plus = prev.buildUBoot {
    defconfig = "generic-rk3528_defconfig";
    extraMeta.platforms = [ "aarch64-linux" ];
    extraMakeFlags = [
      "BL31=${prev.rkbin}/bin/rk35/rk3528_bl31_v1.20.elf"
      "ROCKCHIP_TPL=${prev.rkbin}/bin/rk35/rk3528_ddr_1056MHz_v1.11.bin"
    ];
    filesToInstall = [
      "u-boot.itb"
      "idbloader.img"
      "u-boot-rockchip.bin"
    ];
    extraMeta = {
      description = "U-Boot (generic RK3528) for FriendlyElec NanoPi NEO3 Plus";
    };
  };

}
