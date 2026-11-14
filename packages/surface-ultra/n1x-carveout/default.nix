# n1x-carveout — GPU carveout memmap module for the Surface Laptop Ultra
#
# `n1x_carveout_memmap` calls memremap_pages(MEMORY_DEVICE_PRIVATE) over the
# GPU carveout ranges that the Surface firmware HIDES from the EFI memory map
# (confirmed with efi=debug: the map jumps 0x1fcffffff -> 0x300000000). Without
# struct pages, the nvidia-open driver's vmap() path WARNs and the machine
# hard-resets when nvidia-drm creates its device. With it loaded (BEFORE
# nvidia), stock nvidia-open 615.78.08+ works: 0 WARNINGs, eDP connected,
# OpenGL 4.6 / Vulkan 1.4 on the 6144-core Blackwell GPU.
#
# Upstream write-up: https://gist.github.com/teo-casares/8b64949638e1952602a7f435bb34d5b8
# (Chapter 3). CAVEAT: ranges are hard-coded for EXPOSED_DISP_FRM = 4 GiB.
# Tracking: https://github.com/NVIDIA/open-gpu-kernel-modules/issues/1521
{
  lib,
  pkgs,
  stdenv,
  sources,
  kernel ? pkgs.linuxPackages_latest.kernel,
  kernelModuleMakeFlags ? [ ],
}:

stdenv.mkDerivation {
  pname = "n1x-carveout-memmap";
  version = "1.0";

  # Individual pinned gist files (fetchurl attrs), assembled into a tree.
  src = null; # unpacked manually from $sources below

  dontUnpack = true;
  dontPatch = true; # postPatch (obj-m append) is unnecessary: the gist Makefile already has obj-m
  # Individual pinned gist files (fetchurl attrs). kbuild requires M=<dir with
  # the module Makefile>, so the Makefile must live directly in the build root
  # and the symlink must exist BEFORE genericBuild runs (buildPhase executes
  # make from the build root; preBuild would be too late because the kbuild
  # descends into M= immediately). NIX_STORE is required by the gcc wrapper
  # (set -eu), pahole is on PATH via kernel.moduleBuildDependencies for BTF.
  preBuild = ''
    ln -sf ${sources.gist.n1xCarveoutMemmapC} n1x_carveout_memmap.c
    ln -sf ${sources.gist.n1xCarveoutMemmapMakefile} Makefile
  '';

  nativeBuildInputs = kernel.moduleBuildDependencies;

  # Build explicitly against the kernel build tree: the upstream Makefile is a
  # bare kbuild shim (obj-m only), so plain `make` has no targets. ARCH must
  # match the target (aarch64 → arm64).
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

  meta = with lib; {
    description = "Creates struct pages (memremap MEMORY_DEVICE_PRIVATE) for the N1X GPU carveout ranges hidden from the EFI memory map";
    longDescription = ''
      Load BEFORE nvidia (softdep nvidia pre: n1x_carveout_memmap, wired by the
      surface-laptop-ultra NixOS module). Ranges 0x200000000-0x2ffffffff and
      0xa1600000-0xb7ffffff; assumes EXPOSED_DISP_FRM = 4 GiB.
    '';
    license = licenses.gpl2Only;
    platforms = [ "aarch64-linux" ];
  };
}
