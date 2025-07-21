{
  description = "A bare-bones NixOS flake for Rockchip RK3582/RK3588 boards";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  };

  outputs = { self, nixpkgs }: {
    overlays.default = import ./overlays/uboot;

    nixosConfigurations.e52c = nixpkgs.lib.nixosSystem {
      # system = "aarch64-linux";
      nixpkgs.hostPlatform = "aarch64-linux";
      modules = [
        # Import the main configuration
        ./e52c-configuration.nix

        # Apply the U-Boot overlay
        ({ config, pkgs, ... }: {
          nixpkgs.overlays = [ self.overlays.default ];
        })
      ];
    };
  };
}
