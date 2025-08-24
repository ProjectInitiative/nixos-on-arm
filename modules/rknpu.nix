# NixOS Configuration for Mainline Rockchip NPU Driver
{ config, lib, pkgs, ... }:

{
  # The mainline "Rocket" driver should be available in newer kernels
  # For now, we need to ensure we have the latest kernel and Mesa
  
  # Use the latest kernel that includes the Rocket driver
  # boot.kernelPackages = pkgs.linuxPackages_latest;
  
  # Enable the DRM accel subsystem for NPU support
  boot.kernelModules = [ "rocket" ];
  
  # Ensure Mesa has NPU support (Mesa 25.3+)
  hardware.graphics = {
    enable = true;
    # enable32Bit = true;
    # Use latest Mesa that includes Rocket Gallium3D driver
    package = pkgs.mesa.drivers;
  };
  
  # Add user to video group for NPU access
  # users.users.${config.users.users.kylepzak.name or "kylepzak"} = {
  #   extraGroups = [ "video" "render" ];
  # };
  
  # Optional: Install NPU development tools
  environment.systemPackages = with pkgs; [
    # Add any NPU-specific tools when they become available
  ];
  
  # Note: This assumes you're using a recent kernel (6.18+ expected)
  # and Mesa 25.3+ which should have the Rocket driver
}
