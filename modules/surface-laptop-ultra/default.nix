# surface-laptop-ultra — NixOS hardware module for the Microsoft Surface Laptop Ultra
#
# Hardware (SKU Surface_Laptop_Ultra_2115, UEFI 7.1.0 Project Mu):
#   SoC   NVIDIA N1X "RTX Spark" (GB10 family, aarch64), MediaTek-derived blocks
#   GPU   10de:2e03 — 6144-core Blackwell RTX, unified memory (carveout 4 GiB)
#   NIC   MediaTek MT7925 Wi-Fi/BT
#   Input keyboard MSHW0794 (045E:0CC7, I2C), touchpad ELAN MSHW0734 (04F3:3358),
#         touchscreen/pen MSHW0735 (1FD2:4003) — all I2C HID
#   EC    Surface SAM MSHW0084 over UART NVDA0240 (8250_mtk), platform MSHW0733
#   Audio MT8901 AFE + SoundWire link 0 (NVDA9100): 2x RT1320 amps + RT721 jack
#   Cam   OV02C10 (RGB) + VD55G1 (IR) behind the mt8991 seninf/camsys/CCU block
#
# Everything known about this port comes from teo-casares' write-up
# (gist 8b64949638e1952602a7f435bb34d5b8) and ikegam's surface-ultra-{camera,misc}
# repos — all pinned in packages/surface-ultra/surface-ultra-sources.nix.
#
# Consumption (from another flake, e.g. a host config):
#   inputs.nixos-on-arm.nixosModules.surface-laptop-ultra
#   ${namespace}.hardware.surface-laptop-ultra = { enable = true; ... };
#
# This module does NOT touch: hostname, users, desktop environment, home-manager,
# networking, secrets — the importing flake owns those. Hardware enablement only.
#
# KNOWN CAVEATS:
#   - unplug USB4 docks before s2idle suspend (usb4_release=0 deliberately NOT
#     set; a bad SSPM USB4 power request can reset the SoC — untested upstream)
#   - nvidia-open: the memmap module is what really fixes the carveout; the
#     pinned nvidia-615.78.08 fallback patch is available in sources but not
#     wired by default
#   - UCM caps RT1320 amp gain at -9 dB: no speaker protection/calibration on
#     Linux — keep volume moderate
#   - webcam needs nvCCU.img extracted from the Windows partition
{
  config,
  lib,
  pkgs,
  ...
}:
with lib;
let
  cfg = config.hardware.surface-laptop-ultra;

  # Pinned sources + all packages, built against the configured kernel.
  slu = pkgs.callPackage ../../packages/surface-ultra {
    kernel = cfg.kernelPackages.kernel;
    inherit (cfg) cameraFirmware ssamUartViaAggregator;
  };
in
{
  options.hardware.surface-laptop-ultra = {
    enable = mkOption {
      type = types.bool;
      default = false;
      description = "Enable the Microsoft Surface Laptop Ultra (NVIDIA N1X) hardware enablement";
    };

    kernelPackages = mkOption {
      type = types.raw;
      default = pkgs.linuxPackages_latest;
      description = "Kernel package set to patch and build out-of-tree modules against (linux 7.x)";
    };

    ssamUartViaAggregator = mkOption {
      type = types.bool;
      default = false;
      description = ''
        Use the surface_aggregator baud-halving quirk (kernel patch 0002)
        instead of the 8250_mtk clock-frequency fix (0001). Exactly one is
        applied either way. Prefer the default (0001, upstreamable).
      '';
    };

    useSsamHelperModules = mkOption {
      type = types.bool;
      default = true;
      description = ''
        Use ikegam's ssam-helper out-of-tree modules (n1x_ssam_uartclk +
        n1x_ssam_clients) with STOCK in-tree SSAM drivers instead of the
        kernel-patch approach. Update-resilient: nothing in-tree is replaced.
        When true, kernel patches 0001/0002/0003 are skipped.
      '';
    };

    enableCamera = mkOption {
      type = types.bool;
      default = true;
      description = "Build and wire the MT8991 camera ISP modules (needs CCU firmware for a working camera)";
    };

    cameraFirmware = mkOption {
      type = types.nullOr types.path;
      default = null;
      description = ''
        Store path to nvCCU.img (extract from the Windows partition with
        surface-ultra-camera/firmware/extract-from-windows.sh). Required for
        a working camera; the modules still build without it.
      '';
    };

    enableThermald = mkOption {
      type = types.bool;
      default = true;
      description = "Enable n1x-thermald (skin ≤ 45 °C via CPU freq capping; emergency at 55.5/62 °C)";
    };

    enableTools = mkOption {
      type = types.bool;
      default = true;
      description = "Install the userspace service scripts (touchpad rebind, backlights, sdw settle, key repeat)";
    };

    extraKernelParams = mkOption {
      type = types.listOf types.str;
      default = [ ];
      description = "Extra kernel command line parameters appended to the SLU set";
    };
  };

  config = mkIf cfg.enable {
    assertions = [
      {
        assertion = cfg.useSsamHelperModules -> !cfg.ssamUartViaAggregator;
        message = "surface-laptop-ultra: ssam-helper modules replace the need for the SSAM kernel patches; useSsamHelperModules and ssamUartViaAggregator are mutually exclusive.";
      }
    ];

    # ------------------------------------------------------------------
    # Kernel & boot
    # ------------------------------------------------------------------
    boot = {
      kernelPackages = mkDefault (cfg.kernelPackages.extend (
        final: prev: {
          kernel = prev.kernel.override {
            # Patches 0001/0002 are mutually exclusive (same UART clock fix);
            # 0001-0003 are skipped when ssam-helper modules carry the fix.
            kernelPatches =
              (prev.kernel.passthru.kernelPatches or [ ])
              ++ slu.kernelPatches;
            structuredExtraConfig = with lib.kernel; {
              # Surface Aggregator Module (EC: battery, charger, thermal, fan)
              SURFACE_AGGREGATOR = module;
              SURFACE_AGGREGATOR_REGISTRY = module;
              SURFACE_PLATFORM_PROFILE = module;
              # MT7925 Wi-Fi/BT
              MT7925E = module;
              MT7925U = module;
              BT_MTK = module;
              # I2C HID (keyboard, touchpad, touchscreen)
              I2C_HID_ACPI = module;
              HID_MULTITOUCH = module;
              # SoundWire audio (MT8901 AFE + RT1320/RT721).
              # NOTE: SND_SOC_MT8901/SOUNDWIRE_MTK are Omarchy-kernel options
              # (NVIDIA MT8901 series) — NOT in vanilla 7.3.1; kconfig errors
              # on unknown options, so they are deliberately omitted.
              SND_SOC_RT1320_SDW = module;
              SND_SOC_RT721_SDCA_SDW = module;
              # Serial (SAM EC link, NVDA0240 on 8250_mtk)
              SERIAL_8250_MTK = module;
            };
          };
        }
      ));

      # Out-of-tree modules. Load order enforced via modprobe softdeps below
      # (n1x_carveout_memmap before nvidia; sdw_pad_drive before
      # soundwire_mtk; n1x_ssam_uartclk before surface_aggregator).
      extraModulePackages =
        [
          slu.n1x-carveout
          slu.n1x-sdw-pads
        ]
        ++ optional cfg.useSsamHelperModules slu.surface-ultra-ssam-helper
        ++ optional cfg.enableCamera slu.surface-ultra-camera;

      # GRUB, NOT Limine: Limine 12.9.3 resets the Project Mu firmware before
      # drawing anything (likely init_memmap() + ConnectController(recursive);
      # limine #521 territory). GRUB works on this firmware.
      loader.grub = {
        enable = mkDefault true;
        efiSupport = mkDefault true;
        device = mkDefault "nodev";
        # Project Mu NVRAM writes are unreliable.
        efiInstallAsRemovable = mkDefault true;
        copyKernels = true;
      };
      loader.efi.canTouchEfiVariables = mkDefault false;

      # Proven N1X kernel command line (teo-casares, omacom/omarchy #15885):
      #   acpi_osi=!             — five ACPI devices (SVP0/SSPM/HFRP/NH1X/NMAP)
      #                            hide themselves from Windows 2022 OSI; without
      #                            this, USB/I2C/SPI (keyboard, touchpad, USB) are DEAD
      #   modprobe.blacklist=gpio_keys — phantom Volume Down from floating MSHW0040
      #                            pins 40/41 floods the console (side buttons lost
      #                            unless n1x-power-button handles pin 46)
      #   module_blacklist=nouveau — Blackwell GB10 needs nvidia-open
      #   pci=hpbussize=0x20     — Omarchy N1X support (USB4 hotplug bridge sizing)
      #   mem_sleep_default=s2idle — only supported sleep on this firmware
      #   console=tty0 acpi=nospcr — display/console plumbing quirks
      #   initramfs_async=0 zswap.enabled=0 — boot reliability
      kernelParams =
        [
          "acpi_osi=!"
          "modprobe.blacklist=gpio_keys"
          "module_blacklist=nouveau"
          "pci=hpbussize=0x20"
          "mem_sleep_default=s2idle"
          "console=tty0"
          "acpi=nospcr"
          "initramfs_async=0"
          "zswap.enabled=0"
        ]
        ++ cfg.extraKernelParams;

      # S0ix for the NVIDIA GPU (Windows parity for s2idle) + load-order contracts.
      extraModprobeConfig = ''
        options nvidia NVreg_EnableS0ixPowerManagement=1
        options nvidia NVreg_OpenRmEnableUnsupportedGpus=1
        softdep nvidia pre: n1x_carveout_memmap
        softdep soundwire_mtk pre: sdw_pad_drive
        softdep surface_aggregator pre: n1x_ssam_uartclk
      '';

      kernelModules = [
        "n1x_carveout_memmap"
        "nvidia"
        "nvidia_modeset"
        "nvidia_uvm"
        "nvidia_drm"
      ];
    };

    # ------------------------------------------------------------------
    # GPU / video
    # ------------------------------------------------------------------
    services.xserver.videoDrivers = mkDefault [ "nvidia" ];
    hardware.nvidia = mkIf (config.hardware.nvidia ? open) {
      open = mkDefault true;
      nvidiaSettings = mkDefault false;
      # Power management off until suspend/resume is verified on this platform.
      powerManagement.enable = mkDefault false;
    };
    hardware.graphics.enable = mkDefault true;

    # ------------------------------------------------------------------
    # Input: udev, libinput, hwdb
    # ------------------------------------------------------------------
    services.udev.extraRules = ''
      # [usb4] keep the USB4 tunnel root ports (NVIDIA 10de:22cf) out of runtime
      # suspend; while suspended, dock devices behind them do not enumerate.
      # (Approach from teo-casares; upstream file: surface-ultra-misc/usb4/)
      ACTION=="add|bind", SUBSYSTEM=="pci", ATTR{vendor}=="0x10de", ATTR{device}=="0x22cf", ATTR{power/control}="on"

      # [touchpad] bind the ELAN 04F3:3358 touchpad to the hid-multitouch class
      # used by Windows Precision Touchpads (palm rejection via Confidence bit).
      ACTION=="add", SUBSYSTEM=="hid", ATTRS{vendor}=="0x04f3", ATTRS{product}=="0x3358", ATTR{driver}!="hid-multitouch", RUN+="${slu.surface-ultra-tools}/bin/n1x-touchpad-ptp"

      # [key-repeat] keyboard key-release reports arrive 20-145 ms late (I2C
      # stall); raise the kernel TTY autorepeat delay to 500 ms for this device.
      ACTION=="add", SUBSYSTEM=="input", KERNEL=="event*", ENV{ID_INPUT_KEYBOARD}=="1", ATTRS{name}=="MSHW0794:00 045E:0CC7 Keyboard", RUN+="${slu.surface-ultra-tools}/bin/kbd-repeat-delay $devnode 500"
    '';

    services.udev.extraHwdb = ''
      # [buttons] floating MSHW0040 pins 40/41 report "Volume Down" held forever.
      # Neutralise them; the real power button is handled separately (gpio_keys
      # is blacklisted, soc_button_array is x86-only).
      evdev:input:b0018v045Ep0CC7*
        KEYBOARD_KEY_70046 = reserved
    '';

    environment.etc."libinput/local-overrides.quirks".text = ''
      # Surface Laptop Ultra (N1X) ELAN touchpad: advertises pressure 0-2048 but
      # real touches report ~20-40, so libinput's pressure threshold (~204)
      # rejects every touch. Ignore the pressure axes; fall back to plain
      # contact detection. (Upstream candidate: INPUT_PROP_PRESSUREPAD, as for
      # Elan 04F3:3355.)
      [Surface Laptop Ultra Touchpad]
      MatchUdevType=touchpad
      MatchBus=i2c
      MatchVendor=0x04F3
      MatchProduct=0x3358
      AttrEventCode=-ABS_MT_PRESSURE;-ABS_PRESSURE;
    '';

    # ------------------------------------------------------------------
    # Audio: UCM profile (RT1320 gain capped at -9 dB) + SoundWire settle
    # ------------------------------------------------------------------
    # Custom UCM profile wired via /etc/alsa/ucm2/conf.d — ALSA merges this
    # over the alsa-ucm-conf package's /share/alsa/ucm2 tree. The card name
    # must match the machine-table entry from kernel patch 0005.
    environment.etc = {
      "alsa/ucm2/conf.d/mt8901-soundwir/MicrosoftCorporation-MicrosoftSurfaceLaptopUltra-124I00142T000M0000000.conf".source =
        "${slu.sources.gist.ucmCardConf}";
      "alsa/ucm2/conf.d/mt8901-soundwir/HiFi-surface-laptop-ultra.conf".source =
        "${slu.sources.gist.ucmHiFiConf}";
    };

    systemd.services.n1x-sdw-settle = mkIf cfg.enableTools {
      description = "One soft SoundWire link reset after the card appears";
      after = [ "sound.target" ];
      wantedBy = [ "sound.target" ];
      serviceConfig = {
        Type = "oneshot";
        ExecStart = "${slu.surface-ultra-tools}/bin/n1x-sdw-settle";
      };
    };

    # ------------------------------------------------------------------
    # Power / thermal
    # ------------------------------------------------------------------
    systemd.services.n1x-thermald = mkIf cfg.enableThermald {
      description = "Surface Laptop Ultra (N1X) skin temperature / SoC power controller";
      after = [ "multi-user.target" ];
      wantedBy = [ "multi-user.target" ];
      serviceConfig = {
        ExecStart = "${slu.n1x-thermald}/bin/n1x-thermald";
        Restart = "on-failure";
        RestartSec = 5;
      };
    };

    # Sleep hook: disable wakeup on the I2C keyboard / touchpad / power button
    # for lid-closed suspends (bag wakeups), restore on resume. From
    # surface-ultra-misc/suspend/surface-ultra-lid-wakeup.
    powerManagement.powerDownCommands = ''
      grep -qs closed /proc/acpi/button/lid/*/state && {
        for d in /sys/bus/i2c/devices/i2c-MSHW0794:00 /sys/bus/i2c/devices/i2c-MSHW0734:00 /sys/bus/platform/devices/MSHW0040:00; do
          [ -w "$d/power/wakeup" ] && echo disabled > "$d/power/wakeup"
        done
      }
    '';
    powerManagement.resumeCommands = ''
      for d in /sys/bus/i2c/devices/i2c-MSHW0794:00 /sys/bus/i2c/devices/i2c-MSHW0734:00 /sys/bus/platform/devices/MSHW0040:00; do
        [ -w "$d/power/wakeup" ] && echo enabled > "$d/power/wakeup"
      done
    '';

    # ------------------------------------------------------------------
    # Tools, services & userspace
    # ------------------------------------------------------------------
    environment.systemPackages =
      optionals cfg.enableTools [ slu.surface-ultra-tools ]
      ++ optionals cfg.enableThermald [ slu.n1x-thermald ]
      ++ optionals cfg.enableCamera [ pkgs.libcamera pkgs.alsa-ucm-conf ];

    # n1x-touchpad-ptp rebind at boot (idempotent; skipped if kernel patch 0004
    # already bound the device as MT_CLS_WIN_8 — the script detects this).
    systemd.services.n1x-touchpad-ptp = mkIf cfg.enableTools {
      description = "Rebind ELAN 04F3:3358 touchpad as MT_CLS_WIN_8";
      after = [ "systemd-udevd.service" ];
      wantedBy = [ "multi-user.target" ];
      serviceConfig = {
        Type = "oneshot";
        ExecStart = "${slu.surface-ultra-tools}/bin/n1x-touchpad-ptp";
        RemainAfterExit = true;
      };
    };

    systemd.packages = optionals cfg.enableTools [ slu.surface-ultra-tools ];
  };
}
