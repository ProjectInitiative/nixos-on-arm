# n1x-sdw-pads — MT8901 SoundWire pad drive strength fix (out-of-tree module)
#
# SoundWire link-0 pads (GPIO66/67) default to 2 mA drive strength, but the
# ACPI PinFunction vendor data ({0x04,0x08} on \_SB.CNT0) asks for 8 mA and
# mtk-sdw ignores it. At 2 mA the SoundWire bus never syncs (bus clash /
# parity storms, "no card from this controller") and no codec attaches.
# This module sets the pad drive through the pinctrl core (paris only
# implements per-group pinconf; each pin is a group) and must load BEFORE
# soundwire_mtk (softdep wired by the surface-laptop-ultra NixOS module).
#
# Upstream candidate: pinctrl/soundwire handling of the ACPI PinFunction data
# (Omarchy kernel 1030-n1x-audio.patch territory).
{
  lib,
  pkgs,
  stdenv,
  sources,
  kernel ? pkgs.linuxPackages_latest.kernel,
  kernelModuleMakeFlags ? [ ],
}:

stdenv.mkDerivation {
  pname = "n1x-sdw-pads";
  version = "1.0";

  # Individual pinned gist files (fetchurl attrs), assembled into a tree.
  src = null; # unpacked manually from $sources below

  dontUnpack = true;
  # kbuild requires M=<dir with the module Makefile> — files live in the build
  # root, symlinked BEFORE genericBuild (buildPhase descends into M=
  # immediately). NIX_STORE is required by the gcc wrapper (set -eu); pahole
  # comes via kernel.moduleBuildDependencies for BTF.
  preBuild = ''
    ln -sf ${sources.gist.sdwPadDriveC} sdw_pad_drive.c
    printf 'obj-m := sdw_pad_drive.o\n' > Makefile
  '';

  nativeBuildInputs = kernel.moduleBuildDependencies;

  # Build explicitly against the kernel build tree (the generated Makefile has
  # obj-m but no default target). ARCH must match the target.
  buildPhase = ''
    runHook preBuild
    make -C ${kernel.dev}/lib/modules/${kernel.modDirVersion}/build M=$(pwd) \
      ARCH=${if kernel.stdenv.hostPlatform.isAarch64 then "arm64" else "x86_64"} \
      KERNELRELEASE=${kernel.modDirVersion} modules
    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall
    make -C ${kernel.dev}/lib/modules/${kernel.modDirVersion}/build M=$(pwd) \
      ARCH=${if kernel.stdenv.hostPlatform.isAarch64 then "arm64" else "x86_64"} \
      KERNELRELEASE=${kernel.modDirVersion} INSTALL_MOD_PATH=$out modules_install
    runHook postInstall
  '';

  # Module options: groups=GPIO66,GPIO67 ma=8 (set via the NixOS module's
  # extraModprobeConfig, matching the vendored n1x-audio-sdw-pads.conf).

  meta = with lib; {
    description = "Sets MT8901 SoundWire link-0 pad (GPIO66/67) drive strength to 8 mA so the RT1320/RT721 codecs attach";
    license = licenses.gpl2Only;
    platforms = [ "aarch64-linux" ];
  };
}
