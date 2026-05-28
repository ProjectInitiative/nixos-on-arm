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
      # NPU (Rocket driver)
      DRM_ACCEL = yes;
      DRM_ACCEL_ROCKET = module;

      # Video encoder (VEPU580) and decoder
      VIDEO_ROCKCHIP_RKVENC = yes;
      VIDEO_ROCKCHIP_VDEC = yes;
      VIDEO_HANTRO = yes;
      VIDEO_HANTRO_ROCKCHIP = yes;
      MEDIA_SUPPORT = yes;
      MEDIA_PLATFORM_SUPPORT = yes;
      MEDIA_CONTROLLER_REQUEST_API = yes;
      VIDEO_MEM2MEM_DECODE_CONFIG = yes;

      # Misc Rockchip
      MMC_SDHCI_ROCKCHIP = yes;
    };
    ignoreConfigErrors = true;
  };

in
  pkgs.linuxPackagesFor customKernelPatched
