{ config, lib, pkgs, ... }:

let
  cfg = config.raspberry-pi-nix;
  isBootloaderUefi = cfg.bootloader == "uefi";
  isBootloaderUboot = cfg.bootloader == "uboot";
  isBootloaderRpi = cfg.bootloader == "rpi";
in {
  systemd.services = {
    "raspberry-pi-firmware-migrate" =
      {
        description = "update the firmware partition";
        wantedBy = [ "multi-user.target" ];
        serviceConfig =
          let
            firmware-path = "/boot/firmware";
            uefi = cfg.uefi.package;
            uboot = cfg.uboot.package;
            kernel = config.boot.kernelPackages.kernel;
            kernel-params = pkgs.writeTextFile {
              name = "cmdline.txt";
              text = ''
                ${lib.strings.concatStringsSep " " config.boot.kernelParams}
              '';
            };
            configTxt = config.hardware.raspberry-pi.config-output;
          in
          {
            Type = "oneshot";
            MountImages =
              "/dev/disk/by-label/${config.raspberry-pi-nix.firmwarePartitionName}:${firmware-path}";
            StateDirectory = "raspberrypi-firmware";
            ExecStart = pkgs.writeShellScript "migrate-rpi-firmware" ''
              shopt -s nullglob

              TARGET_FIRMWARE_DIR="${firmware-path}"
              TARGET_OVERLAYS_DIR="$TARGET_FIRMWARE_DIR/overlays"
              TMPFILE="$TARGET_FIRMWARE_DIR/tmp"
              UEFI="${uefi}/RPI_EFI.fd"
              UBOOT="${uboot}/u-boot.bin"
              KERNEL="${kernel}/Image"
              SHOULD_UEFI=${if isBootloaderUefi then "1" else "0"}
              SHOULD_UBOOT=${if isBootloaderUboot then "1" else "0"}
              SHOULD_RPI_BOOT=${if isBootloaderRpi then "1" else "0"}
              SRC_FIRMWARE_DIR="${pkgs.raspberrypifw}/share/raspberrypi/boot"
              STARTFILES=("$SRC_FIRMWARE_DIR"/start*.elf)
              DTBS=("$SRC_FIRMWARE_DIR"/*.dtb)
              BOOTCODE="$SRC_FIRMWARE_DIR/bootcode.bin"
              FIXUPS=("$SRC_FIRMWARE_DIR"/fixup*.dat)
              SRC_OVERLAYS_DIR="$SRC_FIRMWARE_DIR/overlays"
              SRC_OVERLAYS=("$SRC_OVERLAYS_DIR"/*)
              CONFIG="${configTxt}"

              migrate_uefi() {
                echo "migrating uefi"
                touch "$STATE_DIRECTORY/uefi-migration-in-progress"
                cp "$UEFI" "$TMPFILE"
                mv -T "$TMPFILE" "$TARGET_FIRMWARE_DIR/RPI_EFI.fd"
                echo "${
                  builtins.toString uefi
                }" > "$STATE_DIRECTORY/uefi-version"
                rm "$STATE_DIRECTORY/uefi-migration-in-progress"
              }

              migrate_uboot() {
                echo "migrating uboot"
                touch "$STATE_DIRECTORY/uboot-migration-in-progress"
                cp "$UBOOT" "$TMPFILE"
                mv -T "$TMPFILE" "$TARGET_FIRMWARE_DIR/u-boot-rpi-arm64.bin"
                echo "${
                  builtins.toString uboot
                }" > "$STATE_DIRECTORY/uboot-version"
                rm "$STATE_DIRECTORY/uboot-migration-in-progress"
              }

              migrate_kernel() {
                echo "migrating kernel"
                touch "$STATE_DIRECTORY/kernel-migration-in-progress"
                cp "$KERNEL" "$TMPFILE"
                mv -T "$TMPFILE" "$TARGET_FIRMWARE_DIR/kernel.img"
                echo "${
                  builtins.toString kernel
                }" > "$STATE_DIRECTORY/kernel-version"
                rm "$STATE_DIRECTORY/kernel-migration-in-progress"
              }

              migrate_cmdline() {
                echo "migrating cmdline"
                touch "$STATE_DIRECTORY/cmdline-migration-in-progress"
                cp "${kernel-params}" "$TMPFILE"
                mv -T "$TMPFILE" "$TARGET_FIRMWARE_DIR/cmdline.txt"
                echo "${
                  builtins.toString kernel-params
                }" > "$STATE_DIRECTORY/cmdline-version"
                rm "$STATE_DIRECTORY/cmdline-migration-in-progress"
              }

              migrate_config() {
                echo "migrating config.txt"
                touch "$STATE_DIRECTORY/config-migration-in-progress"
                cp "$CONFIG" "$TMPFILE"
                mv -T "$TMPFILE" "$TARGET_FIRMWARE_DIR/config.txt"
                echo "${configTxt}" > "$STATE_DIRECTORY/config-version"
                rm "$STATE_DIRECTORY/config-migration-in-progress"
              }

              migrate_firmware() {
                echo "migrating raspberrypi firmware"
                touch "$STATE_DIRECTORY/firmware-migration-in-progress"
                for SRC in "''${STARTFILES[@]}" "''${DTBS[@]}" "$BOOTCODE" "''${FIXUPS[@]}"
                do
                  cp "$SRC" "$TMPFILE"
                  mv -T "$TMPFILE" "$TARGET_FIRMWARE_DIR/$(basename "$SRC")"
                done

                if [[ ! -d "$TARGET_OVERLAYS_DIR" ]]; then
                  mkdir "$TARGET_OVERLAYS_DIR"
                fi

                for SRC in "''${SRC_OVERLAYS[@]}"
                do
                  cp "$SRC" "$TMPFILE"
                  mv -T "$TMPFILE" "$TARGET_OVERLAYS_DIR/$(basename "$SRC")"
                done
                echo "${
                  builtins.toString pkgs.raspberrypifw
                }" > "$STATE_DIRECTORY/firmware-version"
                rm "$STATE_DIRECTORY/firmware-migration-in-progress"
              }

              if [[ "$SHOULD_UEFI" -eq 1 ]] && [[ -f "$STATE_DIRECTORY/uefi-migration-in-progress" || ! -f "$STATE_DIRECTORY/uefi-version" || $(< "$STATE_DIRECTORY/uefi-version") != ${
                builtins.toString uefi
              } ]]; then
                migrate_uefi
              fi

              if [[ "$SHOULD_UBOOT" -eq 1 ]] && [[ -f "$STATE_DIRECTORY/uboot-migration-in-progress" || ! -f "$STATE_DIRECTORY/uboot-version" || $(< "$STATE_DIRECTORY/uboot-version") != ${
                builtins.toString uboot
              } ]]; then
                migrate_uboot
              fi

              if [[ "$SHOULD_RPI_BOOT" -eq 1 ]] && [[ ! -f "$STATE_DIRECTORY/kernel-version" || $(< "$STATE_DIRECTORY/kernel-version") != ${
                builtins.toString kernel
              } ]]; then
                migrate_kernel
              fi

              if [[ "$SHOULD_RPI_BOOT" -eq 1 ]] && [[ ! -f "$STATE_DIRECTORY/cmdline-version" || $(< "$STATE_DIRECTORY/cmdline-version") != ${
                builtins.toString kernel-params
              } ]]; then
                migrate_cmdline
              fi

              if [[ -f "$STATE_DIRECTORY/config-migration-in-progress" || ! -f "$STATE_DIRECTORY/config-version" || $(< "$STATE_DIRECTORY/config-version") != ${
                builtins.toString configTxt
              } ]]; then
                migrate_config
              fi

              if [[ -f "$STATE_DIRECTORY/firmware-migration-in-progress" || ! -f "$STATE_DIRECTORY/firmware-version" || $(< "$STATE_DIRECTORY/firmware-version") != ${
                builtins.toString pkgs.raspberrypifw
              } ]]; then
                migrate_firmware
              fi
            '';
          };
      };
  };
}