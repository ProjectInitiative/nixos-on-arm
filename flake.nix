{
  description = "A bare-bones NixOS flake for Rockchip RK3582/RK3588 boards";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

    disko = {
      url = "github:nix-community/disko";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, disko }: {
    overlays.default = import ./overlays/uboot;

    nixosConfigurations.e52c = nixpkgs.lib.nixosSystem {
      # system = "aarch64-linux";
      modules = [
        disko.nixosModules.disko
        # Import the main configuration
        ./e52c-configuration.nix
        # ./boot-test.nix
        # ./image.nix

        # Apply the U-Boot overlay
        ({ config, pkgs, ... }: {
          nixpkgs.overlays = [ self.overlays.default ];
        })
      ];
    };
  };
}
