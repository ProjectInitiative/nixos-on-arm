# kernel.nix - Mainline kernel + NanoPi NEO3 Plus board device tree
#
# RK3528 support is in mainline, but there is no NanoPi NEO3 Plus DTS
# upstream yet, so this builds the stock nixpkgs kernel (same base as the
# shared `linuxPackages` flake output) and injects the board DTS from
# ./rk3528-nanopi-neo3-plus.dts into the kernel source tree.
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
in
  pkgs.linuxPackagesFor customKernel
