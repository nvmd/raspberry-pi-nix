{ config, lib, pkgs, ... }:

{
  # Default config.txt on Raspberry Pi OS:
  # https://github.com/RPi-Distro/pi-gen/blob/master/stage1/00-boot-files/files/config.txt
  hardware.raspberry-pi.config = {
    cm4 = {
      options = {
        otg_mode = {
          enable = lib.mkDefault true;
          value = lib.mkDefault true;
        };
      };
    };
    pi4 = {
      options = {
        arm_boost = {
          enable = lib.mkDefault true;
          value = lib.mkDefault true;
        };
      };
    };
    all = {
      options = {
        arm_64bit = {
          enable = true;
          value = true;
        };
        enable_uart = {
          enable = true;
          value = true;
        };
        avoid_warnings = {
          enable = lib.mkDefault true;
          value = lib.mkDefault true;
        };
        camera_auto_detect = {
          enable = lib.mkDefault true;
          value = lib.mkDefault true;
        };
        display_auto_detect = {
          enable = lib.mkDefault true;
          value = lib.mkDefault true;
        };
        disable_overscan = {
          enable = lib.mkDefault true;
          value = lib.mkDefault true;
        };
      };
      dt-overlays = {
        vc4-kms-v3d = {
          enable = lib.mkDefault true;
          params = { };
        };
      };
    };
  };
}