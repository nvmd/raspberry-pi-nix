{ config, lib, pkgs, ... }:

{
  hardware.raspberry-pi.config = {
    all = {
      options = {
        # The firmware will start our u-boot binary rather than a
        # linux kernel.
        kernel = {
          enable = lib.mkDefault true;
          value = "u-boot-rpi-arm64.bin";
        };
      };
    };
  };
}