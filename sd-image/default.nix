{ config, lib, pkgs, ... }:

{
  imports = [ ./sd-image.nix ];

  config = {
    boot.loader.grub.enable = false;

    boot.consoleLogLevel = lib.mkDefault 7;

    # https://github.com/raspberrypi/firmware/issues/1539#issuecomment-784498108
    boot.kernelParams = [ "console=serial0,115200n8" "console=tty1" ];

    sdImage =
      let
        cfg = config.raspberry-pi-nix;

        kernel = config.boot.kernelPackages.kernel;
        kernel-params = pkgs.writeTextFile {
          name = "cmdline.txt";
          text = ''
            ${lib.strings.concatStringsSep " " config.boot.kernelParams}
          '';
        };

        uefi = {
          "4" = (pkgs.fetchzip {
                  url = "https://github.com/pftf/RPi4/releases/download/v1.36/RPi4_UEFI_Firmware_v1.36.zip";
                  hash = "sha256-XWwutTPp7znO5w1XDEUikBNsRK74h0llxnIWIwaxhZc=";
                  stripRoot = false;
                });
          "5" = (pkgs.fetchzip {
                  url = "https://github.com/worproject/rpi5-uefi/releases/download/v0.3/RPi5_UEFI_Release_v0.3.zip";
                  hash = "sha256-bjEvq7KlEFANnFVL0LyexXEeoXj7rHGnwQpq09PhIb0=";
                  stripRoot = false;
                });
        }.${toString cfg.uefi.variant};

        populate-uboot = ''
          cp ${pkgs.uboot_rpi_arm64}/u-boot.bin firmware/u-boot-rpi-arm64.bin
        '';
        populate-kernel = ''
          cp "${kernel}/Image" firmware/kernel.img
          cp "${kernel-params}" firmware/cmdline.txt
        '';
        populate-uefi = ''
          # uefi packages also contain some .dtb file, we get it from
          # `pkgs.raspberrypifw` instead
          cp ${uefi}/RPI_EFI.fd firmware
          ${config.system.build.installBootLoader} ${config.system.build.toplevel} -d firmware
        '';

        populate-bootloader =
          if cfg.uboot.enable then populate-uboot
          else if cfg.rpi-bootloader.enable then populate-kernel
          else if cfg.uefi.enable then populate-uefi
          else (builtins.throw "invalid bootloader option");
      in
      {
        populateFirmwareCommands = ''
          ${populate-bootloader}
          cp -r ${pkgs.raspberrypifw}/share/raspberrypi/boot/{start*.elf,*.dtb,bootcode.bin,fixup*.dat,overlays} firmware
          cp ${config.hardware.raspberry-pi.config-output} firmware/config.txt
        '';
        populateRootCommands =
          if cfg.uboot.enable then ''
            mkdir -p ./files/boot
            ${config.boot.loader.generic-extlinux-compatible.populateCmd} -c ${config.system.build.toplevel} -d ./files/boot
          ''
          else if cfg.rpi-bootloader.enable then ''
            mkdir -p ./files/sbin
            content="$(
              echo "#!${pkgs.bash}/bin/bash"
              echo "exec ${config.system.build.toplevel}/init"
            )"
            echo "$content" > ./files/sbin/init
            chmod 744 ./files/sbin/init
          ''
          else if cfg.uefi.enable then ''''
          else (builtins.throw "invalid bootloader option");
      };
  };
}
