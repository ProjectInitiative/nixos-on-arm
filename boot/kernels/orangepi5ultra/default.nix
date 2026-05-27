{ config, pkgs, lib, ... }:

{
  boot.kernelPackages = lib.mkForce (import ./kernel.nix { inherit pkgs lib; });
}