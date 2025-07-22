{
  config,
  lib,
  pkgs,
  ...
}:

with lib;

let
  ubootIdbloaderFile = "${pkgs.uboot-rk3582-generic}/idbloader.img";
  ubootItbFile = "${pkgs.uboot-rk3582-generic}/u-boot.itb";
in
{
  config = {
    system.build.bootloader-test-image = pkgs.runCommand "bootloader-test.img" {
      nativeBuildInputs = [
        pkgs.coreutils
      ];

      inherit ubootIdbloaderFile ubootItbFile;

    } ''
      set -ex
      local imageName=$out

      dd if=/dev/zero of=$imageName bs=1M count=32

      dd if=$ubootIdbloaderFile of=$imageName bs=512 seek=64 conv=notrunc

      dd if=$ubootItbFile of=$imageName bs=512 seek=16384 conv=notrunc

      echo "Minimal bootloader test image created successfully at $out"
    '';
  };
}
