# surface-ultra-tools — userspace services & scripts for the Surface Laptop Ultra
#
# Userspace pieces from the teo-casares gist (pinned per-file in
# surface-ultra-sources.nix), packaged without modification:
#
#   n1x-touchpad-ptp         rebinds the ELAN 04F3:3358 touchpad as
#                            MT_CLS_WIN_8 via a dynamic hid-multitouch id —
#                            the runtime fallback when kernel patch 0004
#                            is not in the kernel
#   kbd-repeat-delay         sets the kernel soft-autorepeat delay on an
#                            evdev node (used by the console udev rule; the
#                            keyboard's key-release reports arrive 20-145 ms
#                            late, so the 250 ms default self-repeats)
#   n1x-edp-backlight        creates /sys/class/leds/nvidia_0::lcd_backlight
#                            (0-100 -> 3-1000 nits over eDP DPCD) through
#                            the NVIDIA RM ioctl interface, persists level
#   surface-kbd-backlight    creates /sys/class/leds/surface::kbd_backlight
#                            (levels 0/3/6/12) over the keyboard's HID
#                            backlight control
#   n1x-sdw-settle           one soft SoundWire link reset after the card
#                            appears (safety net for a half-initialised
#                            jack codec)
{
  lib,
  stdenvNoCC,
  bash,
  python3,
  makeWrapper,
  gawk,
  gnugrep,
  coreutils,
  kmod,
  sources,
}:

stdenvNoCC.mkDerivation {
  pname = "surface-ultra-tools";
  version = "unstable-2026-11-13";

  # Individual pinned gist files (fetchurl attrs) assembled into a tree.
  src = null; # unpackPhase wires the pinned fetchurl attrs directly

  nativeBuildInputs = [ makeWrapper ];

  dontBuild = true;

  unpackPhase = ''
    runHook preUnpack
    mkdir -p source
    ln -s ${sources.gist.n1xTouchpadPtp} source/n1x-touchpad-ptp
    ln -s ${sources.gist.kbdRepeatDelay} source/kbd-repeat-delay
    ln -s ${sources.gist.n1xEdpBacklight} source/n1x-edp-backlight
    ln -s ${sources.gist.n1xEdpBacklightService} source/n1x-edp-backlight.service
    ln -s ${sources.gist.surfaceKbdBacklight} source/surface-kbd-backlight
    ln -s ${sources.gist.surfaceKbdBacklightService} source/surface-kbd-backlight.service
    ln -s ${sources.gist.n1xSdwSettle} source/n1x-sdw-settle
    ln -s ${sources.gist.n1xSdwSettleService} source/n1x-sdw-settle.service
    cd source
    runHook postUnpack
  '';

  installPhase = ''
    runHook preInstall
    mkdir -p $out/bin $out/lib/systemd/system

    install -Dm755 n1x-touchpad-ptp $out/bin/n1x-touchpad-ptp
    install -Dm755 kbd-repeat-delay $out/bin/kbd-repeat-delay
    install -Dm755 n1x-edp-backlight $out/bin/n1x-edp-backlight
    install -Dm755 surface-kbd-backlight $out/bin/surface-kbd-backlight
    install -Dm755 n1x-sdw-settle $out/bin/n1x-sdw-settle

    for svc in n1x-edp-backlight n1x-sdw-settle n1x-touchpad-ptp surface-kbd-backlight; do
      install -Dm644 $svc.service $out/lib/systemd/system/$svc.service
      substituteInPlace $out/lib/systemd/system/$svc.service \
        --replace-fail "/usr/local/sbin/$svc" "$out/bin/$svc" \
        --replace-fail "/usr/local/bin/$svc" "$out/bin/$svc"
    done
    runHook postInstall
  '';

  postFixup = ''
    # python3 shebang script (uses only the stdlib)
    wrapProgram $out/bin/kbd-repeat-delay \
      --prefix PATH : ${lib.makeBinPath [ python3 coreutils ]}
    # bash scripts need standard tools
    for s in n1x-touchpad-ptp n1x-edp-backlight surface-kbd-backlight n1x-sdw-settle; do
      wrapProgram $out/bin/$s \
        --prefix PATH : ${lib.makeBinPath [ bash gawk gnugrep coreutils kmod ]}
    done
  '';

  meta = with lib; {
    description = "Userspace services and scripts for the Surface Laptop Ultra (touchpad PTP rebind, eDP/keyboard backlights, SoundWire settle, key repeat)";
    platforms = [ "aarch64-linux" ];
  };
}
