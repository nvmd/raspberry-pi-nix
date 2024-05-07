{ config, lib, pkgs, ... }:

let
  cfg = config.hardware.raspberry-pi;
in {
  hardware.raspberry-pi.config = {
    all = {
      options = {
        armstub = {
          enable = lib.mkDefault true;
          value = "RPI_EFI.fd";
        };
        device_tree_address = {
          enable = lib.mkDefault true;
          value = lib.mkDefault "0x1f0000";
        };
        device_tree_end = {
          enable = lib.mkDefault true;
          value = lib.mkDefault ({
            "4" = "0x200000";
            "5" = "0x210000";
          }.${toString cfg.rpi-variant});
        };
        framebuffer_depth = {
          # Force 32 bpp framebuffer allocation.
          enable = lib.mkDefault (cfg.rpi-variant == 5);
          value = 32;
        };
        disable_commandline_tags = {
          enable = lib.mkDefault (cfg.rpi-variant == 4);
          value = 1;
        };
        uart_2ndstage = {
          enable = lib.mkDefault (cfg.rpi-variant == 4);
          value = 1;
        };
        enable_gic = {
          enable = lib.mkDefault (cfg.rpi-variant == 4);
          value = 1;
        };
      };
      dt-overlays = {
        miniuart-bt = {
          enable = lib.mkDefault (cfg.rpi-variant == 4);
          params = { };
        };
        upstream-pi4 = {
          enable = lib.mkDefault (cfg.rpi-variant == 4);
          params = { };
        };
      };
    };
  };
}