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

        uefi = cfg.uefi.package;
        uboot = cfg.uboot.package;

        populate-uboot = ''
          cp ${uboot}/u-boot.bin firmware/u-boot-rpi-arm64.bin
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

        populate-bootloader = {
          uefi = populate-uefi;
          uboot = populate-uboot;
          rpi = populate-kernel;
        }.${cfg.bootloader};
      in
      {
        populateFirmwareCommands = ''
          ${populate-bootloader}
          cp -r ${pkgs.raspberrypifw}/share/raspberrypi/boot/{start*.elf,*.dtb,bootcode.bin,fixup*.dat,overlays} firmware
          cp ${config.hardware.raspberry-pi.config-output} firmware/config.txt
        '';
        populateRootCommands = {
          uefi = '''';
          uboot = ''
            mkdir -p ./files/boot
            ${config.boot.loader.generic-extlinux-compatible.populateCmd} -c ${config.system.build.toplevel} -d ./files/boot
          '';
          rpi = ''
            mkdir -p ./files/sbin
            content="$(
              echo "#!${pkgs.bash}/bin/bash"
              echo "exec ${config.system.build.toplevel}/init"
            )"
            echo "$content" > ./files/sbin/init
            chmod 744 ./files/sbin/init
          '';
        }.${cfg.bootloader};
      };
  };
}
