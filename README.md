# NixOS Rockchip RK3582 Image Builder

This project creates NixOS disk images for Rockchip RK3582-based boards (specifically the Radxa E52C) with proper U-Boot integration and multiple image variants.

## File Structure

```
.
├── configuration.nix              # Main NixOS configuration
├── modules/
│   └── rockchip-image.nix        # Rockchip support module
├── assemble-monolithic-image.nix  # Image assembly function
└── README.md                      # This file
```

## How It Works

### 1. `configuration.nix`
- Main system configuration file
- Enables the Rockchip module and configures board-specific settings
- Sets build platform (x86_64) and host platform (aarch64)
- Configures which image variants to build

### 2. `modules/rockchip-image.nix`
- NixOS module that provides the `rockchip.*` configuration options
- Sets up UKI (Unified Kernel Image) boot with systemd-boot
- Configures device tree, kernel parameters, and hardware-specific settings
- Uses NixOS's `repart` system to create boot and root filesystem images
- Calls the image assembler to create final disk images

### 3. `assemble-monolithic-image.nix`
- Function that combines U-Boot, boot partition, and root partition into complete disk images
- Creates proper GPT partition tables
- Supports multiple image variants:
  - **Full Image**: Complete eMMC-style image with U-Boot included
  - **OS Image**: SD card-style image without U-Boot (assumes U-Boot already on device)
  - **U-Boot Only**: Just the U-Boot components for separate flashing

## Configuration Options

### Board Selection
```nix
rockchip = {
  enable = true;
  board = "rk3582-radxa-e52c";  # Currently supported board
};
```

### Console Settings
```nix
rockchip.console = {
  earlycon = "uart8250,mmio32,0xfeb50000";  # Early console for boot debugging
  console = "ttyS4,1500000";                # Main console
};
```

### Image Variants
```nix
rockchip.image.buildVariants = {
  full = true;       # Build nixos-e52c-full.img (for eMMC)
  sdcard = true;     # Build os-only.img (for SD card)
  ubootOnly = false; # Build uboot-only.img
};
```

### Image Layout
```nix
rockchip.image = {
  bootPartitionStartMB = 16;    # Boot partition offset for full images
  osBootPartitionStartMB = 1;   # Boot partition offset for SD card images
};
```

## Building Images

### Build All Configured Variants
```bash
nix-build -A config.system.build.rockchipImages
```

### Build Just the Primary Image
```bash
nix-build -A config.system.build.image
```

### Results
The build will create a `result/` directory containing:
- `nixos-e52c-full.img` - Complete eMMC image (if enabled)
- `os-only.img` - SD card image (if enabled)
- `default.img` - Symlink to the primary image

## Flashing Images

### eMMC (Full Image)
```bash
# Flash complete image to eMMC
sudo dd if=result/nixos-e52c-full.img of=/dev/mmcblk0 bs=1M status=progress sync
```

### SD Card (OS Only)
```bash
# Flash OS-only image to SD card (requires U-Boot already on device)
sudo dd if=result/os-only.img of=/dev/sdb bs=1M status=progress sync
```

## Image Layout

### Full Image (eMMC)
```
Sector 0      : MBR/GPT header
Sector 64     : U-Boot idbloader
Sector 16384  : U-Boot ITB (u-boot.itb)
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

1. **Hardware Boot ROM** loads U-Boot idbloader from fixed location
2. **U-Boot idbloader** initializes RAM and loads main U-Boot
3. **U-Boot** finds boot partition and loads UKI (Unified Kernel Image)
4. **UKI** contains kernel, initrd, and command line in a single EFI executable
5. **Kernel** boots and mounts root filesystem by label
6. **First Boot** automatically expands root partition to fill available space

## Features

- **UKI Boot**: Modern unified kernel image approach
- **Automatic Resize**: Root partition expands on first boot
- **Multiple Variants**: Build for different deployment scenarios
- **Proper GPT**: Full GPT partition table support
- **Hardware Support**: Rockchip-specific kernel modules and firmware

## Customization

### Adding New Boards
Add board configuration to `boardConfigs` in `modules/rockchip-image.nix`:

```nix
boardConfigs = {
  "rk3582-radxa-e52c" = { /* existing */ };
  "your-new-board" = {
    deviceTree = "rockchip/your-board.dtb";
    defaultUboot = pkgs.uboot-your-board;
    defaultConsole = {
      earlycon = "uart8250,mmio32,0x...";
      console = "ttyS0,115200";
    };
  };
};
```

### Custom U-Boot Package
```nix
rockchip.uboot.package = pkgs.callPackage ./custom-uboot.nix {};
```

### Additional System Packages
```nix
environment.systemPackages = with pkgs; [
  # Add your packages here
  vim git htop
];
```

## Troubleshooting

### Build Fails with Missing Files
- Ensure U-Boot package provides `idbloader.img` and `u-boot.itb`
- Check that repart successfully created boot and root images

### Boot Fails
- Verify console settings match your hardware
- Check U-Boot offset sectors are correct for your board
- Ensure device tree name is correct

### Image Too Small
- Increase `imagePaddingMB` in the assembler parameters
- Check that root partition has enough space for the NixOS closure

## Dependencies

- NixOS with repart support
- Cross-compilation support (x86_64 → aarch64)  
- U-Boot package for your board
- Appropriate device tree blobs
