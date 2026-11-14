# Surface Laptop Ultra (N1X) — pinned upstream sources
#
# Single place for every external source the SLU packages/modules build
# from. Update a pin here; every consumer follows.
#
# Sources:
#   - teo-casares gist (kernel patches, DKMS modules, services, configs):
#       https://gist.github.com/teo-casares/8b64949638e1952602a7f435bb34d5b8
#     Gists have no commit pinning, so we pin the raw per-file URLs the gist
#     API reports (revision 219814edf... recorded 2026-11-13). Upstreaming
#     any file changes its raw_url, so a drift fails the hash — deliberate:
#     SLU patches are kernel-version-sensitive and must not float silently.
#   - ikegam/surface-ultra-camera @ e95a232 (2026-11-10): MT8991 camera ISP
#   - ikegam/surface-ultra-misc   @ 4d00dbc (2026-11-12): thermald, ssam-helper,
#     power button, suspend hooks, USB4 rules
#
# To update: `nix store prefetch-file --unpack <url> --json` to pre-compute a
# hash, or bump the pin and copy the "got: sha256-…" from the build error.
{
  fetchurl,
  fetchFromGitHub,
}:

let
  gistBase = "https://gist.githubusercontent.com/teo-casares/8b64949638e1952602a7f435bb34d5b8/raw";

  # Per-file pinned fetch of the gist artifacts.
  gistFile = name: hash:
    fetchurl {
      url = gistBase + "/${name}";
      inherit hash;
    };
in
{
  # --- gist artifacts -----------------------------------------------------
  gist = {
    inherit gistFile;

    n1xCarveoutMemmapC = gistFile "n1x_carveout_memmap.c" "sha256-1JDex+SliqE7QCUB9JZfP+ra8hHVaAjZcjkk+2q0PVE=";
    n1xCarveoutMemmapMakefile = gistFile "n1x_carveout_memmap.Makefile" "sha256-uWielXrD+GTCmSd8AD7eM+jfzp3B2oLh3uc/gmcPOYg=";
    n1xCarveoutMemmapModprobe = gistFile "n1x-carveout-memmap.modprobe.conf" "sha256-K0g5FID+zkW+CbpSsSQbV+MkFMmDvQL7JohrHRq77yk=";
    n1xCarveoutPatch = gistFile "nvidia-615.78.08-n1x-carveout.patch" "sha256-+AJqJqzNDMcBRuhyq4oGegcJ0ZlK442d9BGA1zFD8y8=";

    sdwPadDriveC = gistFile "sdw_pad_drive.c" "sha256-xzR0GVqMC9q1cVkxGg2T7Erwj98ZfOqjIbbmCXI1lKw=";
    n1xAudioSdwPadsConf = gistFile "n1x-audio-sdw-pads.conf" "sha256-Gd3BseoKy+lN28RgJN84syZERtByjMPxla0DV7QKykM=";
    surfaceUltraMachPatch = gistFile "surface-ultra-mach.patch" "sha256-YIPjPMSE5LI2undVvLEmK7zat9b0ItGVSpXKGtATAbs=";

    surfaceN1xSsamPatch = gistFile "surface-n1x-ssam.patch" "sha256-4fh6JdbCBgeTThXFwNn40nVfmGIKy6UJ0AaDyPg2R7U=";
    staged8250MtkPatch = gistFile "STAGED-8250_mtk-nvda0240-52mhz.patch" "sha256-QxG0XBcmfzq24a3VQ9QY2gaxJ/BwjEOcjYfZbNvJSIg=";

    ucmCardConf = gistFile "MicrosoftCorporation-MicrosoftSurfaceLaptopUltra-124I00142T000M0000000.conf" "sha256-pumgvAB7uLzhivFqTu/4I+bu3P3JWYX55S+cV4j5/Ko=";
    ucmHiFiConf = gistFile "HiFi-surface-laptop-ultra.conf" "sha256-0+LJNB04soU+gDVOS+pIj6u5TwASaqODHtGSDC548ak=";

    touchpadQuirks = gistFile "surface-laptop-ultra-touchpad.quirks" "sha256-VBvSJ367oTstPiIvmlrfpPoSjGWsZOPHPMP+jvi/6RA=";
    keyRepeatRules = gistFile "71-key-repeat-surface-kbd.rules" "sha256-IpeU0wPR5D9WUVpl5FuI0utWDXvJEla2xwNJY98K/v8=";
    kbdRepeatDelay = gistFile "kbd-repeat-delay" "sha256-rkEGF077nxcSrY/RQ/5bSCbfPhfssgRpTLl8yaDO0jU=";
    n1xTouchpadPtp = gistFile "n1x-touchpad-ptp" "sha256-FTxx04ZQQC5Xoo0830u3zJBHOxeks6QPWzDEhjhYWqw=";
    n1xTouchpadPtpService = gistFile "n1x-touchpad-ptp.service" "sha256-Ev0R5Lj+VSh8zqLi7onRB2WWJzA/Sy6F+xS7m+lZswY=";
    n1xEdpBacklight = gistFile "n1x-edp-backlight" "sha256-GZ3+VVDULnkCTEEH9oNAdvvVZhHMao9U5Usq4VVsaxA=";
    n1xEdpBacklightService = gistFile "n1x-edp-backlight.service" "sha256-K/WG3lmLUs8sjbTDmknJwnMj6S05N2ur4DbzGlZcDFs=";
    surfaceKbdBacklight = gistFile "surface-kbd-backlight" "sha256-m82g5aBMAsiaAtmmrfkc88uQrZ1FBFVUd5F1Z0oxHZc=";
    surfaceKbdBacklightService = gistFile "surface-kbd-backlight.service" "sha256-aqLLSXhDtAj9T00qKMXmR91uSOr5w2mmdvNVGKd6GtA=";
    n1xSdwSettle = gistFile "n1x-sdw-settle" "sha256-ZEjf6y1znQVPifJVFvUq7lCiUd8s+vHdZTvDk7qsnGk=";
    n1xSdwSettleService = gistFile "n1x-sdw-settle.service" "sha256-RKzl5ZI1f6dRHEVKhr7WlmureZgktftypNBqFhphAIw=";
    n1xDkmsGuard = gistFile "n1x-dkms-guard" "sha256-xeI1CB6kz+pSUozz0FfglZVUxduLffh8KwCccTor0/w=";
  };

  # --- ikegam repos --------------------------------------------------------
  surface-ultra-camera = fetchFromGitHub {
    owner = "ikegam";
    repo = "surface-ultra-camera";
    rev = "e95a23202f3a1c260f4e61476d0b0d464ebfba56";
    hash = "sha256-snGWMUS/CE9nMc0deFFIyl7akQzD9qUxFYapDIyT3SA=";
  };

  surface-ultra-misc = fetchFromGitHub {
    owner = "ikegam";
    repo = "surface-ultra-misc";
    rev = "4d00dbc292672de95de715e5e810c9860433d1a3";
    hash = "sha256-+p0vlQlfJaIJR5iA8R5EMF1DnlR90AikWG+Rb5aq/6Q=";
  };
}
