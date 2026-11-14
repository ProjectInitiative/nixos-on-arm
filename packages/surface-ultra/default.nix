# surface-ultra — Surface Laptop Ultra (NVIDIA RTX Spark N1X) build-enablement packages
#
# All out-of-tree kernel modules, daemons, and userspace tools needed to get
# the SLU daily-drivable on NixOS. The NixOS module that wires everything
# (patches, load order, udev, services) is modules/surface-laptop-ultra.
#
# Sources are pinned in surface-ultra-sources.nix (fetchurl/fetchFromGitHub —
# nothing vendored in-repo).
#
# Exposed via the flake as packages.<system>.surface-ultra-* and consumed by
# other flakes (e.g. dotfiles) through nixos-on-arm's nixosModules.
{
  lib,
  pkgs,
  symlinkJoin,
  callPackage,
  fetchurl,
  fetchFromGitHub,

  # The kernel to build out-of-tree modules against. Override per-host; the
  # NixOS module passes its patched kernelPackages.kernel here.
  kernel ? pkgs.linuxPackages_latest.kernel,
  # Kernel module make flags passthrough (for cross builds).
  kernelModuleMakeFlags ? [ ],
  # Store path to nvCCU.img (extract from the machine's Windows partition —
  # see surface-ultra-camera docs). null = camera modules build without firmware.
  cameraFirmware ? null,
  # Use the DKMS-style aggregator baud quirk (kernel patch 0002) instead of
  # the 8250_mtk clock-frequency fix (0001).
  ssamUartViaAggregator ? false,
}:

let
  sources = callPackage ./surface-ultra-sources.nix { inherit fetchurl fetchFromGitHub; };

  n1x-carveout = callPackage ./n1x-carveout {
    inherit sources kernel kernelModuleMakeFlags;
  };

  n1x-sdw-pads = callPackage ./n1x-sdw-pads {
    inherit sources kernel kernelModuleMakeFlags;
  };

  surface-ultra-camera = callPackage ./surface-ultra-camera {
    inherit sources kernel kernelModuleMakeFlags cameraFirmware;
  };

  surface-ultra-ssam-helper = callPackage ./surface-ultra-ssam-helper {
    inherit sources kernel kernelModuleMakeFlags;
  };

  n1x-thermald = callPackage ./n1x-thermald { inherit sources; };

  surface-ultra-tools = callPackage ./surface-ultra-tools { inherit sources; };

  kernelPatches = callPackage ./kernel-patches/slu-patches.nix {
    inherit ssamUartViaAggregator;
  };
in
{
  inherit
    sources
    n1x-carveout
    n1x-sdw-pads
    surface-ultra-camera
    surface-ultra-ssam-helper
    n1x-thermald
    surface-ultra-tools
    kernelPatches
    ;

  # Aggregate (symlink join of everything)
  all = symlinkJoin {
    name = "surface-ultra-${kernel.modDirVersion}";
    paths = [
      n1x-carveout
      n1x-sdw-pads
      surface-ultra-camera
      surface-ultra-ssam-helper
      n1x-thermald
      surface-ultra-tools
    ];
    meta = with lib; {
      description = "All out-of-tree modules, daemons and tools for the Microsoft Surface Laptop Ultra (NVIDIA RTX Spark N1X, aarch64)";
      platforms = [ "aarch64-linux" ];
    };
  };
}
