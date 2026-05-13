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

## Building Strategy (Hybrid vs. Full Cross-Compilation)

By default, this project uses a **Hybrid Building Approach** when building on `x86_64` for `aarch64`. 

### 1. **Hybrid Mode (Default)**
*   **System Binaries**: Evaluated as native `aarch64-linux` (pulls from official NixOS cache via QEMU for small tasks).
*   **Image Assembly**: Uses native `x86_64` host tools (`sfdisk`, `mtools`, `truncate`, `dd`).
*   **Benefit**: Fastest overall build. You get cache hits for the standard NixOS system while keeping disk-intensive image creation native and reliable.

### 2. **Kernel-Only Cross-Compilation (Current Best Practice)**
*  **Kernel**: Cross-compiled from `x86_64` → `aarch64` via `linuxPackagesCross` (fast, avoids QEMU for the kernel).
*  **Everything else**: Native `aarch64-linux`, pulled from official NixOS cache.
*  **Benefit**: Avoids the 6-hour QEMU kernel build without rebuilding the entire system. This is what `nix build .#e52c-boot-cross` does.

### 3. **Full Cross-Compilation (Slow initial, cached after)**
*   **System Binaries**: Formally cross-compiled from `x86_64` to `aarch64`.
*   **Image Assembly**: Uses native `x86_64` host tools.
*   **Benefit**: Every package cross-compiled once, cached forever. Good for CI pipelines.
*   **Downside**: First build rebuilds everything from source (different derivation hashes than official cache).

### Future Exploration: Content-Addressed Fallback

Nix's content-addressed derivations (CA) are an experimental feature where the output hash is derived from the **content**, not the build inputs. This would allow:

- Evaluate as full cross-compilation (all derivations use `aarch64-unknown-linux-gnu-gcc`)
- If the cross-compiled output is byte-for-byte identical to a cached native binary, Nix skips the build
- If not (e.g., a package that inlines `__DATE__` or has target-specific code), it builds from source

This gives the "try native cache first, fall back to cross-compile" behavior, but with a clean architecture. It requires:

1. Enabling `__contentAddressed` on the relevant derivations
2. Changes in nixpkgs to mark packages as CA
3. A CI pipeline that builds cross packages and seeds the cache

For now, the kernel-only cross approach (`*-boot-cross`) is the best tradeoff for individual developers. Full cross-compilation with CA is worth revisiting when Nix's CA support matures.

### Consuming the Cross-Compiled Kernel

Other flakes can use the cross-compiled kernel directly via the exported `linuxPackagesCross` output:

```nix
{
  inputs.nixos-on-arm.url = "github:kylepzak/nixos-on-arm";

  outputs = { self, nixpkgs, nixos-on-arm, ... }: {
    nixosConfigurations.myboard = nixpkgs.lib.nixosSystem {
      modules = [
        ({ pkgs, lib, ... }: {
          nixpkgs.hostPlatform = "aarch64-linux";
          # Cross-compiled kernel (x86_64 → aarch64), rest from cache
          boot.kernelPackages = lib.mkForce nixos-on-arm.linuxPackagesCross.x86_64-linux;
        })
      ];
    };
  };
}
```

Or use the pre-built configs directly:

```bash
nix build 'github:kylepzak/nixos-on-arm#e52c-boot-cross'
```

All `*-boot-cross` and `*-demo-cross` variants are available in both `packages` and `nixosConfigurations` outputs.

### How to Switch

To switch to **Full Cross-Compilation**, modify `flake.nix` in the `mkBoardConfiguration` function:

```nix
# Edit flake.nix:
nixpkgs.lib.nixosSystem {
  modules = modules ++ [
    ({ pkgs, ... }: {
      # ...
      nixpkgs.buildPlatform = buildSystem; # <--- ADD THIS LINE
      nixpkgs.hostPlatform = boards.${board}.hostPlatform;
      # ...
    })
  ];
}
```

Adding `nixpkgs.buildPlatform = buildSystem;` triggers the formal cross-compiler (full system rebuild, slow initially). Removing it (default) restores Hybrid/Emulated mode with only the kernel cross-compiled.

---

* **🚀 Cross-Platform**: Build from x86\_64 or native ARM
* **🎯 Variant System**: Boot-only vs demo images per board
* **📦 UKI Boot**: Unified kernel image booting
* **🛡️ GPT Layout**: Proper GPT partitioning
* **⚡ Hardware Support**: Rockchip-specific drivers & firmware
* **🔄 Reproducible**: Fully declarative with Nix flakes

---
