{ config, lib, pkgs, ... }:

{
  hardware.raspberry-pi.config = {
    all = {
      options = {
        kernel = {
          enable = lib.mkDefault true;
          value = "kernel.img";
        };
      };
    };
  };
}