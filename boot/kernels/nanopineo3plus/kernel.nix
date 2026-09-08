# kernel.nix - Mainline kernel + NanoPi NEO3 Plus board device tree
#
# RK3528 support is in mainline, but there is no NanoPi NEO3 Plus DTS
# upstream yet, so this builds the stock nixpkgs kernel (same base as the
# shared `linuxPackages` flake output) and injects the board DTS from
# ./rk3528-nanopi-neo3-plus.dts into the kernel source tree.
#
# USB support: RK3528 USB (USB2PHY + DWC3/EHCI/OHCI nodes) has not landed
# upstream as of 6.18/7.0, so the Armbian rockchip64-6.18 rk3528 USB
# patches are applied (based on Jonas Karlman's mainlining work):
#   - phy: inno-usb2 RK3528 support (+ standalone PHY regmap split)
#   - rk3528.dtsi USB controller/PHY node definitions
#   - OTG delayed-work cleanup fix
{ pkgs, lib ? pkgs.lib }:

let
  baseKernel = pkgs.linuxPackages.kernel.override {
    # Keep in sync with the shared `linuxPackages` output in flake.nix
    extraConfig = ''
      FW_LOADER_COMPRESS y
      FW_LOADER_COMPRESS_ZSTD y
    '';
  };

  customKernel = baseKernel.overrideAttrs (oldAttrs: {
    postPatch = (oldAttrs.postPatch or "") + ''
      dtsDir=arch/arm64/boot/dts/rockchip
      cp ${./rk3528-nanopi-neo3-plus.dts} $dtsDir/rk3528-nanopi-neo3-plus.dts
      if ! grep -q rk3528-nanopi-neo3-plus $dtsDir/Makefile; then
        if grep -q rk3528-nanopi-zero2.dtb $dtsDir/Makefile; then
          sed -i '/rk3528-nanopi-zero2.dtb/a\dtb-$(CONFIG_ARCH_ROCKCHIP) += rk3528-nanopi-neo3-plus.dtb' $dtsDir/Makefile
        else
          # Fallback for kernel versions without the Zero2 DTS: append at EOF
          echo 'dtb-$(CONFIG_ARCH_ROCKCHIP) += rk3528-nanopi-neo3-plus.dtb' >> $dtsDir/Makefile
        fi
      fi
    '';
  });

  customKernelPatched = customKernel.override {
    kernelPatches = (baseKernel.kernelPatches or [ ]) ++ [
      {
        name = "rk3528-phy-inno-usb2";
        patch = ./patches/rk3528-10-phy-rockchip-inno-usb2-Add-support-for-RK3528.patch;
      }
      {
        name = "rk3528-dtsi-usb-nodes";
        patch = ./patches/rk3528-11-arm64-dts-rockchip-rk3528-Add-USB-controller-and-PHY-nodes.patch;
      }
      {
        name = "rk3528-phy-inno-usb2-otg-cleanup";
        patch = ./patches/rk3528-13-phy-rockchip-inno-usb2-fix-otg-timer-cleanup.patch;
      }
    ];
  };
in
  pkgs.linuxPackagesFor customKernelPatched
