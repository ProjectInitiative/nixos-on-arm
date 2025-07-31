# NixOS Rockchip ARM Board Image Builder

This project creates NixOS disk images for Rockchip ARM-based boards with proper U-Boot integration, cross-compilation support, and multiple image variants. Currently supports the Radxa E52C (RK3582) with a modular design for easy addition of new boards.

## File Structure

```
.
├── flake.nix                       # Nix flake with board-specific outputs
├── e52c-configuration.nix          # E52C board configuration
├── modules/
│   ├── rockchip-image.nix          # Rockchip support module
│   ├── assemble-monolithic-image.nix # Image assembly function
│   └── make-fat-fs.nix             # FAT32 filesystem builder
├── overlays/
│   └── uboot/                      # U-Boot patches and overlay
└── README.md                       # This file
```

## How It Works

### 1. **Flake Structure (`flake.nix`)**
- Provides board-specific build targets with automatic cross-compilation support
- Auto-detects build platform (x86_64 or aarch64) for optimal performance
- Supports explicit cross-compilation and native builds
- Modular design for easy addition of new boards

### 2. **Board Configuration (`e52c-configuration.nix`)**
- Board-specific NixOS configuration
- Enables the Rockchip module and configures hardware settings
- Sets up networking, users, and system packages
- Configures which image variants to build

### 3. **Rockchip Module (`modules/rockchip-image.nix`)**
- NixOS module providing `rockchip.*` configuration options
- Sets up UKI (Unified Kernel Image) boot with systemd-boot
- Configures device tree, kernel parameters, and hardware-specific settings
- Creates boot (FAT32) and root (ext4) filesystem images
- Calls the image assembler to create final disk images

### 4. **Image Assembler (`modules/assemble-monolithic-image.nix`)**
- Combines U-Boot, boot partition, and root partition into complete disk images
- Creates proper GPT partition tables with correct offsets
- Supports multiple image variants for different deployment scenarios

## Supported Boards

| Board | SoC | Status | Configuration File |
|-------|-----|--------|-------------------|
| Radxa E52C | RK3582 | ✅ Supported | `e52c-configuration.nix` |
| Radxa E25 | RK3568 | 🚧 Planned | `e25-configuration.nix` |
| Radxa Rock 5B | RK3588 | 🚧 Planned | `rock5b-configuration.nix` |

## Building Images

### Quick Start

```bash
# Auto-detect build platform and build E52C images:
nix build .#e52c

# Explicit cross-compilation from x86_64:
nix build .#e52c-cross

# Native ARM build (on ARM host):
nix build .#e52c-native
```

### Available Build Targets

| Target | Description | Build Platform | Host Platform |
|--------|-------------|----------------|---------------|
| `.#e52c` | Auto-detect current system | Current system | aarch64-linux |
| `.#e52c-cross` | Cross-compile from x86_64 | x86_64-linux | aarch64-linux |
| `.#e52c-native` | Native ARM build | aarch64-linux | aarch64-linux |
| `.#default` | Alias for `.#e52c` | Current system | aarch64-linux |

### System-Specific Builds

```bash
# Build using x86_64 as build platform:
nix build .#packages.x86_64-linux.e52c

# Build using aarch64 as build platform:
nix build .#packages.aarch64-linux.e52c
```

### Legacy Commands (still supported)

```bash
# Build all configured variants:
nix-build -A config.system.build.rockchipImages

# Build primary image only:
nix-build -A config.system.build.image
```

## Build Results

The build creates a `result/` directory containing:
- `nixos-rockchip-full.img` - Complete eMMC image with U-Boot
- `nixos-rockchip-os-only.img` - SD card image without U-Boot
- `nixos-rockchip-uboot-only.img` - U-Boot only image (if enabled)

## Configuration Options

### Board Selection and Variants
```nix
rockchip = {
  enable = true;
  
  # U-Boot configuration
  uboot.package = pkgs.uboot-rk3582-generic;
  deviceTree = "rockchip/rk3582-radxa-e52c.dtb";
  
  # Console settings
  console = {
    earlycon = "uart8250,mmio32,0xfeb50000";
    console = "ttyS4,1500000";
  };
  
  # Image variants to build
  image.buildVariants = {
    full = true;       # eMMC image with U-Boot
    sdcard = true;     # SD card image without U-Boot
    ubootOnly = false; # U-Boot only image
  };
};
```

### Cross-Compilation Settings
The flake automatically handles cross-compilation settings, but you can customize:

```nix
# In your board configuration:
nixpkgs = {
  buildPlatform = "x86_64-linux";   # Auto-set by flake
  hostPlatform = "aarch64-linux";   # Always ARM target
  config.allowUnsupportedSystem = true;
};
```

## Flashing Images

### eMMC (Full Image)
```bash
# Flash complete image to eMMC
sudo dd if=result/nixos-rockchip-full.img of=/dev/mmcblk0 bs=1M status=progress sync
```

### SD Card (OS Only)
```bash
# Flash OS-only image to SD card (requires U-Boot already on device)
sudo dd if=result/nixos-rockchip-os-only.img of=/dev/sdb bs=1M status=progress sync
```

### U-Boot Only (for recovery)
```bash
# Flash just U-Boot to eMMC (preserves existing partitions)
sudo dd if=result/nixos-rockchip-uboot-only.img of=/dev/mmcblk0 bs=1M status=progress sync
```

## Image Layout

### Full Image (eMMC)
```
Sector 0      : MBR/GPT header
Sector 64     : U-Boot idbloader.img
Sector 16384  : U-Boot u-boot.itb
Sector 32768  : Boot partition (FAT32 with UKI)
Sector X      : Root partition (ext4 with NixOS)
```

### OS Image (SD Card)
```
Sector 0     : MBR/GPT header  
Sector 2048  : Boot partition (FAT32 with UKI)
Sector Y     : Root partition (ext4 with NixOS)
```

## Boot Process

1. **Hardware Boot ROM** loads U-Boot idbloader from sector 64
2. **U-Boot idbloader** initializes RAM and loads main U-Boot from sector 16384
3. **U-Boot** finds FAT32 boot partition and loads `EFI/BOOT/BOOTAA64.EFI` (UKI)
4. **UKI** contains kernel, initrd, and command line in a single EFI executable
5. **Kernel** boots and mounts root filesystem by label `NIXOS_ROOT`
6. **First Boot** automatically expands root partition to fill available space

## Adding New Boards

### 1. Create Board Configuration
Create a new file like `new-board-configuration.nix`:

```nix
{ config, pkgs, lib, ... }:
{
  imports = [ ./modules/rockchip-image.nix ];
  
  rockchip = {
    enable = true;
    uboot.package = pkgs.uboot-new-board;
    deviceTree = "rockchip/new-board.dtb";
    console = {
      earlycon = "uart8250,mmio32,0x...";
      console = "ttyS0,115200";
    };
    image.buildVariants = {
      full = true;
      sdcard = true;
    };
  };
  
  # Board-specific configuration...
}
```

### 2. Add to Flake
Update `flake.nix` to include the new board:

```nix
boards = {
  e52c = {
    hostPlatform = "aarch64-linux";
    configFile = ./e52c-configuration.nix;
    description = "Radxa E52C (RK3582)";
  };
  new-board = {
    hostPlatform = "aarch64-linux";
    configFile = ./new-board-configuration.nix;
    description = "Your New Board";
  };
};
```

### 3. Enable in Outputs
Uncomment the relevant lines in `nixosConfigurations` and `packages` sections of the flake.

### 4. Build Commands
```bash
nix build .#new-board         # Auto-detect build platform
nix build .#new-board-cross   # Cross-compile
nix build .#new-board-native  # Native build
```

## Development

### Development Shell
```bash
nix develop
# Provides nixos-rebuild, git, and helpful build commands
```

### Debugging Builds
```bash
# Show detailed build trace:
nix build .#e52c --show-trace

# Build with debug output:
nix build .#e52c -L

# Check flake outputs:
nix flake show
```

### Testing Cross-Compilation
```bash
# Force cross-compilation even on ARM:
nix build --system x86_64-linux .#packages.x86_64-linux.e52c-cross

# Test native build even on x86_64 (requires binfmt):  
nix build --system aarch64-linux .#packages.aarch64-linux.e52c-native
```

## Features

- **🚀 Cross-Platform**: Builds efficiently on x86_64 or natively on ARM
- **🎯 Board-Specific**: Clean separation of board configurations
- **🔧 Multiple Variants**: eMMC, SD card, and U-Boot only images
- **📦 UKI Boot**: Modern unified kernel image approach
- **📈 Auto-Resize**: Root partition expands on first boot
- **🛡️ Proper GPT**: Full GPT partition table support
- **⚡ Hardware Support**: Rockchip-specific drivers and firmware
- **🔄 Reproducible**: Fully declarative with Nix flakes

## Troubleshooting

### Build Issues
- **"attribute missing"**: Make sure you're using the correct flake target (`.#e52c`, not `.#e52c-cross` for packages)
- **Cross-compilation fails**: Ensure `allowUnsupportedSystem = true` is set
- **U-Boot missing**: Check that your U-Boot package provides `idbloader.img` and `u-boot.itb`

### Boot Issues
- **No console output**: Verify console settings match your hardware
- **U-Boot not found**: Check U-Boot sector offsets (64 and 16384)
- **Kernel panic**: Ensure device tree name matches your board

### Image Issues
- **Image too small**: Increase `imagePaddingMB` in rockchip module
- **Partition errors**: Verify GPT table with `gdisk -l result/image.img`

## Dependencies

- **NixOS/Nixpkgs**: Latest unstable for ARM support
- **Cross-compilation**: Automatically configured by flake
- **U-Boot**: Board-specific package with Rockchip patches
- **Device Trees**: Linux kernel device tree blobs
- **ARM Trusted Firmware**: For RK3588/RK3582 support
