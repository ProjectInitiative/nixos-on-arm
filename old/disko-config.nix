# disko-config.nix
{ lib, pkgs, config, ... }:

let
  bootVolumeLabel = "NIXOS_BOOT";
  rootVolumeLabel = "NIXOS_ROOT";
in
{
  disko.devices.disk.main = {
    type = "disk";
    device = "/dev/vda"; # This is a placeholder for the image builder
    imageSize = "4G";    # Create a 4GB image, which will be grown on first boot
    content = {
      type = "gpt";
      partitions = {
        boot = {
          # Size from Rockchip vendor map: 229376 sectors * 512 = 112MiB
          size = "112M";
          type = "EF00"; # ESP partition type
          content = {
            type = "filesystem";
            format = "vfat";
            mountpoint = "/boot";
          };
          label = bootVolumeLabel;
        };
        root = {
          # Use the rest of the 4GB image
          size = "100%";
          content = {
            type = "filesystem";
            format = "ext4";
            mountpoint = "/";
            extraArgs = [ "-L ${rootVolumeLabel}" ];
          };
        };
      };
    };
  };
}
