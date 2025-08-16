# NixOS Rockchip ARM Board Image Builder

This project creates NixOS disk images for Rockchip ARM-based boards with proper U-Boot integration, cross-compilation support, and **multiple image variants (boot-only, demo, etc.)**.
Currently supports the Radxa E52C (RK3582) and Radxa Rock 5A (RK3588S), with a modular design for easy addition of new boards.

## File Structure

```
.
├── flake.nix                       # Nix flake with board + variant outputs
├── e52c-configuration.nix          # E52C board configuration
├── rock5a-configuration.nix        # Rock 5A board configuration
├── modules/
│   ├── rockchip-image.nix          # Rockchip support module
│   ├── assemble-monolithic-image.nix # Image assembly function
│   └── make-fat-fs.nix             # FAT32 filesystem builder
├── overlays/
│   └── uboot/                      # U-Boot patches and overlay
└── README.md                       # This file
```

---

## How It Works

### 1. **Flake Structure (`flake.nix`)**

* Provides **board + variant** build targets with automatic cross-compilation support
* Auto-detects build platform (x86\_64 or aarch64) for optimal performance
* Supports explicit cross-compilation and native builds
* Modular design: each board can expose multiple variants (e.g. `boot`, `demo`)

### 2. **Board Configurations**

* Each board has its own config file (`e52c-configuration.nix`, `rock5a-configuration.nix`)
* Imports the `rockchip-image.nix` module
* Defines hardware-specific U-Boot, DTB, console, and image variants
* Board-specific tweaks (networking, packages, users) go here

### 3. **Modules**

* **rockchip-image.nix** → adds UKI boot, GPT partitioning, image variants
* **assemble-monolithic-image.nix** → glues together bootloader + partitions
* **make-fat-fs.nix** → helper to construct FAT32 boot partitions

---

## Supported Boards

| Board         | SoC     | Variants       | Status      |
| ------------- | ------- | -------------- | ----------- |
| Radxa E52C    | RK3582  | `demo`, `boot` | ✅ Supported |
| Radxa Rock 5A | RK3588S | `demo`, `boot` | ✅ Supported |
| Radxa E25     | RK3568  | TBD            | 🚧 Planned  |
| Radxa Rock 5B | RK3588  | TBD            | 🚧 Planned  |

---

## Building Images

### Quick Start

```bash
# Build the default (demo) image for E52C:
nix build .#e52c

# Build an explicit variant:
nix build .#e52c-demo   # demo image with extra packages
nix build .#e52c-boot   # minimal boot-only image

# Build Rock 5A:
nix build .#rock5a
nix build .#rock5a-demo
nix build .#rock5a-boot
```

### Available Build Targets

| Target          | Description                                       |
| --------------- | ------------------------------------------------- |
| `.#e52c`        | Alias → `e52c-demo`                               |
| `.#e52c-demo`   | E52C with demo config (extra packages, dev tools) |
| `.#e52c-boot`   | Minimal E52C boot-only image                      |
| `.#rock5a`      | Alias → `rock5a-demo`                             |
| `.#rock5a-demo` | Rock 5A with demo config                          |
| `.#rock5a-boot` | Minimal Rock 5A boot-only image                   |

---

## Cross-Compilation

Cross vs native is **automatic**:

* On x86\_64 → images are cross-compiled for ARM (`aarch64-linux`)
* On ARM → images build natively

Example:

```bash
# Build E52C on x86_64 (cross)
nix build .#packages.x86_64-linux.e52c

# Build E52C on aarch64 host (native)
nix build .#packages.aarch64-linux.e52c
```

---

## Flashing Images

Same as before:

```bash
# eMMC full image
sudo dd if=result/nixos-rockchip-full.img of=/dev/mmcblk0 bs=1M status=progress sync

# SD card OS-only
sudo dd if=result/nixos-rockchip-os-only.img of=/dev/sdb bs=1M status=progress sync
```

---

## Adding New Boards

1. Create a config file (`myboard-configuration.nix`) that imports `./modules/rockchip-image.nix` and sets `rockchip.*`.
2. Add your board to `flake.nix` in `bootModules` and/or `demoModules`.
3. Add build targets under `packages`:

```nix
myboard-demo = mkImg "myboard" self.demoModules.myboard;
myboard-boot = mkImg "myboard" self.bootModules.myboard;
myboard = mkImg "myboard" self.demoModules.myboard; # alias
```

4. Build:

```bash
nix build .#myboard
nix build .#myboard-demo
nix build .#myboard-boot
```

---

## Using as a flake Dependency

You can import this flake into another project’s `flake.nix` to reuse board builds:

```nix
{
  inputs = {
    nixos-on-arm.url = "github:projectinitiative/nixos-on-arm";
  };

  outputs = { self, nixpkgs, nixos-on-arm, ... }:
  let
    system = "x86_64-linux"; # or aarch64-linux
  in {
    packages.${system}.my-custom-build =
      nixos-on-arm.packages.${system}.e52c-demo;
  };
}
```

Then build with:

```bash
nix build .#my-custom-build
```

This way you can layer your own configuration on top while reusing the Rockchip base logic.

---

## Using as a config Dependency

Using in Another Configuration

You can also import the board base configs into your own NixOS configuration.
The flake provides reusable module sets under demoModules.<board> and bootModules.<board>.

Example: use the Rock5A demo setup inside your own config:

{ inputs, ... }:

{
  imports =
    inputs.nixos-on-arm.demoModules.rock5a
    ++ [
      ./my-networking.nix
      ./users.nix
    ];
}

Or, for a minimal boot-only base:

{
  imports =
    inputs.nixos-on-arm.bootModules.e52c
    ++ [
      ./my-services.nix
    ];
}

This way, you can treat the board setup as a foundation, while layering on your own modules and configs.

---

## Features

* **🚀 Cross-Platform**: Build from x86\_64 or native ARM
* **🎯 Variant System**: Boot-only vs demo images per board
* **📦 UKI Boot**: Unified kernel image booting
* **🛡️ GPT Layout**: Proper GPT partitioning
* **⚡ Hardware Support**: Rockchip-specific drivers & firmware
* **🔄 Reproducible**: Fully declarative with Nix flakes

---
