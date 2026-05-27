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

      &vdec0 {
        status = "okay";
      };

      &vdec0_mmu {
        status = "okay";
      };

      &vdec1 {
        status = "okay";
      };

      &vdec1_mmu {
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

      &av1d_mmu {
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
      ARCH_ROCKCHIP = yes;
      VIDEO_ROCKCHIP_RKVENC = yes;
      VIDEO_ROCKCHIP_VDEC = yes;
      VIDEO_HANTRO = yes;
      VIDEO_HANTRO_ROCKCHIP = yes;
      MEDIA_CONTROLLER_REQUEST_API = yes;
      VIDEO_MEM2MEM_DECODE_CONFIG = yes;
      MMC_DW_ROCKCHIP = yes;
      MMC_SDHCI_ROCKCHIP = yes;
    };
    ignoreConfigErrors = true;
  };

in
  pkgs.linuxPackagesFor customKernelPatched