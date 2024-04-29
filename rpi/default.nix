{ core-overlay, libcamera-overlay }:
{ lib, pkgs, config, ... }:

let cfg = config.raspberry-pi-nix;
in
{
  imports = [ ./config.nix ./i2c.nix ];

  options = with lib; {
    raspberry-pi-nix = {
      rpi-variant = mkOption {
        default = 4;
        type = types.enum [ 4 5 ];
        description = ''
          Target RaspberryPi device variant: 4 or 5.
        '';
      };
      firmware-migration-service = {
        enable = mkOption {
          default = true;
          type = types.bool;
          description = ''
            Whether to run the migration service automatically or not.
          '';
        };
      };
      core-overlay = {
        enable = mkOption {
          default = true;
          type = types.bool;
          description = ''
            If enabled then the "core overlay" is applied which
            adds `rpi-kernels` packages set, and overrides raspberrypi firmware
            packages.
          '';
        };
      };
      libcamera-overlay = {
        enable = mkOption {
          default = true;
          type = types.bool;
          description = ''
            If enabled then the libcamera overlay is applied which
            overrides libcamera with the rpi fork.
          '';
        };
      };
      bootloader = mkOption {
        default = "uboot";
        type = types.enum [ "rpi" "uboot" "uefi" ];
        description = lib.mdDoc ''
          Bootloader to use:
          - `"uefi"`: EDK2 UEFI firmware. See also `uefi.package`.
          - `"uboot"`: U-Boot
          - `"rpi"`: The linux kernel is installed directly into the
            firmware directory as expected by the raspberry pi boot
            process.

            This can be useful for newer hardware that doesn't yet have
            uboot compatibility or less common setups, like booting a
            cm4 with an nvme drive.
        '';
      };
      uboot = {
        package = mkPackageOption pkgs "uboot_rpi_arm64" { };
      };
      uefi = {
        package = mkOption {
          default = {
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
          }.${toString cfg.rpi-variant};
          type = types.package;
          description = lib.mdDoc ''
            UEFI firmware to use, depending on `rpi-variant` option value:
            - "4" for https://github.com/pftf/RPi4/
            - "5" for https://github.com/worproject/rpi5-uefi/.
            Alternatively, package can be specified directly with `uefi.package`.
          '';
        };
      };

      firmwarePartitionID = mkOption {
        type = types.str;
        default = "0x2178694e";
        description = ''
          Volume ID for the /boot/firmware partition on the SD card. This value
          must be a 32-bit hexadecimal number.
        '';
      };

      firmwarePartitionName = mkOption {
        type = types.str;
        default = "FIRMWARE";
        description = ''
          Name of the filesystem which holds the boot firmware.
        '';
      };
    };
  };

  config = let
    isBootloaderUefi = cfg.bootloader == "uefi";
    isBootloaderUboot = cfg.bootloader == "uboot";
    isBootloaderRpi = cfg.bootloader == "rpi";
  in {
    boot.kernelParams = {
      uefi = [];
      uboot = [];
      rpi = [
        # This is ugly and fragile, but the sdImage image has an msdos
        # table, so the partition table id is a 1-indexed hex
        # number. So, we drop the hex prefix and stick on a "02" to
        # refer to the root partition.
        "root=PARTUUID=${lib.strings.removePrefix "0x" config.raspberry-pi-nix.firmwarePartitionID}-02"
        "rootfstype=ext4"
        "fsck.repair=yes"
        "rootwait"
        "init=/sbin/init"
      ];
    }.${cfg.bootloader};
    systemd.services = {
      "raspberry-pi-firmware-migrate" =
        {
          description = "update the firmware partition";
          wantedBy = if cfg.firmware-migration-service.enable then [ "multi-user.target" ] else [ ];
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
          # The firmware will start our u-boot binary rather than a
          # linux kernel.
          kernel = lib.mkIf (isBootloaderUboot || isBootloaderRpi) {
            enable = true;
            value = {
              uboot = "u-boot-rpi-arm64.bin";
              rpi = "kernel.img";
            }.${cfg.bootloader};
          };
          armstub = {
            enable = lib.mkDefault isBootloaderUefi;
            value = "RPI_EFI.fd";
          };
          device_tree_address = {
            enable = lib.mkDefault isBootloaderUefi;
            value = lib.mkDefault "0x1f0000";
          };
          device_tree_end = {
            enable = lib.mkDefault isBootloaderUefi;
            value = lib.mkDefault ({
              "4" = "0x200000";
              "5" = "0x210000";
            }.${toString cfg.rpi-variant});
          };
          framebuffer_depth = {
            # Force 32 bpp framebuffer allocation.
            enable = lib.mkDefault (isBootloaderUefi && cfg.rpi-variant == 5);
            value = 32;
          };
          disable_commandline_tags = {
            enable = lib.mkDefault (isBootloaderUefi && cfg.rpi-variant == 4);
            value = 1;
          };
          uart_2ndstage = {
            enable = lib.mkDefault (isBootloaderUefi && cfg.rpi-variant == 4);
            value = 1;
          };
          enable_gic = {
            enable = lib.mkDefault (isBootloaderUefi && cfg.rpi-variant == 4);
            value = 1;
          };
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
          miniuart-bt = {
            enable = lib.mkDefault (isBootloaderUefi && cfg.rpi-variant == 4);
            params = { };
          };
          upstream-pi4 = {
            enable = lib.mkDefault (isBootloaderUefi && cfg.rpi-variant == 4);
            params = { };
          };
        };
      };
    };

    nixpkgs = {
      overlays = lib.optionals cfg.core-overlay.enable [ core-overlay ]
              ++ lib.optionals cfg.libcamera-overlay.enable [ libcamera-overlay ];
    };
    boot = {
      initrd.availableKernelModules = [
        "usbhid"
        "usb_storage"
        "vc4"
        "pcie_brcmstb" # required for the pcie bus to work
        "reset-raspberrypi" # required for vl805 firmware to load
      ];
      kernelPackages = lib.mkDefault (pkgs.linuxPackagesFor (pkgs.rpi-kernels.latest.kernel));

      loader = {
        grub.enable = lib.mkDefault false;
        initScript.enable = isBootloaderRpi;
        generic-extlinux-compatible = {
          enable = lib.mkDefault isBootloaderUboot;
          # We want to use the device tree provided by firmware, so don't
          # add FDTDIR to the extlinux conf file.
          useGenerationDeviceTree = false;
        };

        efi = lib.mkIf isBootloaderUefi {
          canTouchEfiVariables = lib.mkDefault false;
        };
        systemd-boot = {
          enable = lib.mkDefault isBootloaderUefi;
        };
      };
    };
    hardware.enableRedistributableFirmware = true;

    services = {
      udev.extraRules =
        let shell = "${pkgs.bash}/bin/bash";
        in ''
          # https://raw.githubusercontent.com/RPi-Distro/raspberrypi-sys-mods/master/etc.armhf/udev/rules.d/99-com.rules
          SUBSYSTEM=="input", GROUP="input", MODE="0660"
          SUBSYSTEM=="i2c-dev", GROUP="i2c", MODE="0660"
          SUBSYSTEM=="spidev", GROUP="spi", MODE="0660"
          SUBSYSTEM=="*gpiomem*", GROUP="gpio", MODE="0660"
          SUBSYSTEM=="rpivid-*", GROUP="video", MODE="0660"

          KERNEL=="vcsm-cma", GROUP="video", MODE="0660"
          SUBSYSTEM=="dma_heap", GROUP="video", MODE="0660"

          SUBSYSTEM=="gpio", GROUP="gpio", MODE="0660"
          SUBSYSTEM=="gpio", KERNEL=="gpiochip*", ACTION=="add", PROGRAM="${shell} -c 'chgrp -R gpio /sys/class/gpio && chmod -R g=u /sys/class/gpio'"
          SUBSYSTEM=="gpio", ACTION=="add", PROGRAM="${shell} -c 'chgrp -R gpio /sys%p && chmod -R g=u /sys%p'"

          # PWM export results in a "change" action on the pwmchip device (not "add" of a new device), so match actions other than "remove".
          SUBSYSTEM=="pwm", ACTION!="remove", PROGRAM="${shell} -c 'chgrp -R gpio /sys%p && chmod -R g=u /sys%p'"

          KERNEL=="ttyAMA[0-9]*|ttyS[0-9]*", PROGRAM="${shell} -c '\
                  ALIASES=/proc/device-tree/aliases; \
                  TTYNODE=$$(readlink /sys/class/tty/%k/device/of_node | sed 's/base/:/' | cut -d: -f2); \
                  if [ -e $$ALIASES/bluetooth ] && [ $$TTYNODE/bluetooth = $$(strings $$ALIASES/bluetooth) ]; then \
                      echo 1; \
                  elif [ -e $$ALIASES/console ]; then \
                      if [ $$TTYNODE = $$(strings $$ALIASES/console) ]; then \
                          echo 0;\
                      else \
                          exit 1; \
                      fi \
                  elif [ $$TTYNODE = $$(strings $$ALIASES/serial0) ]; then \
                      echo 0; \
                  elif [ $$TTYNODE = $$(strings $$ALIASES/serial1) ]; then \
                      echo 1; \
                  else \
                      exit 1; \
                  fi \
          '", SYMLINK+="serial%c"

          ACTION=="add", SUBSYSTEM=="vtconsole", KERNEL=="vtcon1", RUN+="${shell} -c '\
          	if echo RPi-Sense FB | cmp -s /sys/class/graphics/fb0/name; then \
          		echo 0 > /sys$devpath/bind; \
          	fi; \
          '"
        '';
    };
  };

}
