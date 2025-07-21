# configuration.nix

{ config, pkgs, ... }:

{
  # Import your new sd-image module.
  # This will pull in all the repart logic and related settings.
  imports = [ ./sd-image.nix ];

  # --- Basic System Configuration ---
  # Keep general settings here.

  networking.hostName = "nixos-rockchip";
  time.timeZone = "Etc/UTC";

  # Define a user account
  users.users.root.initialHashedPassword = "";
  users.users.nixos = {
    isNormalUser = true;
    extraGroups = [ "wheel" ]; # Enable sudo
    initialHashedPassword = "";
  };

  # Minimal packages to include in the image
  environment.systemPackages = with pkgs; [
    vim
    git
  ];

  # Set the system state version
  system.stateVersion = "24.11"; # Match the version in your sd-image.nix
}
