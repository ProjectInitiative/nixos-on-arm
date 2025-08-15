final: prev: {
  uboot-rk3582-generic = prev.buildUBoot {
    pname = "uboot-rk3582-generic";
    defconfig = "generic-rk3588_defconfig";
    
    extraPatches = [
      ./patches/0001-rockchip-Add-initial-RK3582-support.patch
      ./patches/0002-rockchip-rk3588-generic-Enable-support-for-RK3582.patch
    ];

    BL31 = "${prev.armTrustedFirmwareRK3588}/bl31.elf";
    ROCKCHIP_TPL = prev.rkbin.TPL_RK3588;
    
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
    BL31 = "${prev.armTrustedFirmwareRK3588}/bl31.elf";
    ROCKCHIP_TPL = prev.rkbin.TPL_RK3588;
    filesToInstall = [
      "u-boot.itb"
      "idbloader.img"
      "u-boot-rockchip.bin"
    ];
  };


}
