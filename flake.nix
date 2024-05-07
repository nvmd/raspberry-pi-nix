{
  description = "raspberry-pi nixos configuration";

  inputs = {
    u-boot-src = {
      flake = false;
      url = "https://ftp.denx.de/pub/u-boot/u-boot-2024.01.tar.bz2";
    };
    rpi-linux-6_1-src = {
      flake = false;
      url = "https://github.com/raspberrypi/linux/archive/refs/tags/stable_20231123.tar.gz?unpack=false";
    };
    rpi-firmware-src = {
      flake = false;
      url = "https://github.com/raspberrypi/firmware/archive/7e6decce72fdff51923e9203db46716835ae889a.tar.gz?unpack=false";
    };
    rpi-firmware-nonfree-src = {
      flake = false;
      url = "github:RPi-Distro/firmware-nonfree/88aa085bfa1a4650e1ccd88896f8343c22a24055";
    };
    rpi-bluez-firmware-src = {
      flake = false;
      url = "github:RPi-Distro/bluez-firmware/d9d4741caba7314d6500f588b1eaa5ab387a4ff5";
    };
    libcamera-apps-src = {
      flake = false;
      url = "github:raspberrypi/libcamera-apps/v1.4.1";
    };
    libcamera-src = {
      flake = false;
      url = "github:raspberrypi/libcamera/563cd78e1c9858769f7e4cc2628e2515836fd6e7"; # v0.1.0+rpt20231122
    };
    libpisp-src = {
      flake = false;
      url = "github:raspberrypi/libpisp/v1.0.3";
    };
  };

  outputs = srcs@{ self, ... }: {
    overlays = {
      core = import ./overlays (builtins.removeAttrs srcs [ "self" ]);
      libcamera = import ./overlays/libcamera.nix (builtins.removeAttrs srcs [ "self" ]);
    };
    nixosModules = {
      raspberry-pi = import ./rpi {
        core-overlay = self.overlays.core;
        libcamera-overlay = self.overlays.libcamera;
      };
      config-txt = {
        generator = import ./rpi/config.nix;

        default = import ./rpi/config-default.nix;
        rpiboot = import ./rpi/config-rpiboot.nix;
        uboot = import ./rpi/config-uboot.nix;
        uefi = import ./rpi/config-uefi.nix;
      };
    };
  };
}
