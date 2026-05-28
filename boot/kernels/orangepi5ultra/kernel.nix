{ pkgs, lib }:

let
  baseKernel = pkgs.linuxPackages_latest.kernel;

  customKernel = baseKernel.overrideAttrs (oldAttrs: {
    postPatch = (oldAttrs.postPatch or "") + ''
      cat >> arch/arm64/boot/dts/rockchip/rk3588-orangepi-5-ultra.dts <<EOF

      &vpu121 {
        status = "okay";
      };

      &vpu121_mmu {
        status = "okay";
      };

      &rkvenc0 {
        status = "okay";
      };

      &rkvenc0_mmu {
        status = "okay";
      };

      &rkvenc1 {
        status = "okay";
      };

      &rkvenc1_mmu {
        status = "okay";
      };

      &av1d {
        status = "okay";
      };
      EOF
    '';
  });

  customKernelPatched = customKernel.override {
    kernelPatches = (baseKernel.kernelPatches or [ ]) ++ [
      {
        name = "rk3588-vepu580-encoder";
        patch = ./patches/0001-rockchip-rk3588-vepu580-encoder-support-v3.patch;
      }
      {
        name = "rk3588-hdmirx-edid-fix";
        patch = ./patches/0002-rockchip-rk3588-hdmirx-edid-fix-v1.patch;
      }
      {
        name = "rk3588-hdmirx-plugout-fix";
        patch = ./patches/0003-rockchip-rk3588-hdmirx-plugout-fix-v1.patch;
      }
    ];
    structuredExtraConfig = with lib.kernel; {
      # SoC
      ARCH_ROCKCHIP = yes;
      ROCKCHIP_PM_DOMAINS = yes;
      ROCKCHIP_IOMMU = yes;
      ROCKCHIP_IODOMAIN = yes;

      # PCIe (NVMe SSD)
      PCIE_ROCKCHIP_HOST = module;

      # Display / DRM
      DRM_ROCKCHIP = module;
      ROCKCHIP_ANALOGIX_DP = yes;
      ROCKCHIP_CDN_DP = yes;
      ROCKCHIP_DW_HDMI = yes;
      ROCKCHIP_DW_MIPI_DSI = yes;
      ROCKCHIP_INNO_HDMI = yes;
      ROCKCHIP_LVDS = yes;
      PWM_ROCKCHIP = yes;

      # GPU (Mali-G610 on RK3588)
      DRM_PANTHOR = module;

      # NPU (Rocket driver for Rockchip RK3588)
      DRM_ACCEL = yes;
      DRM_ACCEL_ROCKET = module;

      # Video encode/decode
      VIDEO_ROCKCHIP_RKVENC = yes;
      VIDEO_ROCKCHIP_VDEC = yes;
      VIDEO_HANTRO = yes;
      VIDEO_HANTRO_ROCKCHIP = yes;
      MEDIA_SUPPORT = yes;
      MEDIA_PLATFORM_SUPPORT = yes;
      MEDIA_CONTROLLER_REQUEST_API = yes;
      VIDEO_MEM2MEM_DECODE_CONFIG = yes;

      # mmc / storage
      MMC_DW_ROCKCHIP = yes;
      MMC_SDHCI_ROCKCHIP = yes;

      # PHYs
      PHY_ROCKCHIP_EMMC = yes;
      PHY_ROCKCHIP_INNO_HDMI = module;
      PHY_ROCKCHIP_INNO_USB2 = yes;
      PHY_ROCKCHIP_TYPEC = yes;
      ROCKCHIP_PHY = yes;

      # Thermal
      ROCKCHIP_THERMAL = module;

      # SPI
      SPI_ROCKCHIP = yes;

      # Audio
      SND_SOC_ROCKCHIP = module;
      SND_SOC_ROCKCHIP_SPDIF = module;
    };
    ignoreConfigErrors = true;
  };

in
  pkgs.linuxPackagesFor customKernelPatched
