{ core-overlay, libcamera-overlay }:
{ lib, pkgs, config, ... }:

let cfg = config.raspberry-pi-nix;
in
{
  imports = [
    ./config.nix ./config-default.nix ./i2c.nix
    ./udev.nix
  ];

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
        description = ''
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
      rpi-boot = {
        rootPartition = mkOption {
          type = types.str;
          # This is ugly and fragile, but the sdImage image has an msdos
          # table, so the partition table id is a 1-indexed hex
          # number. So, we drop the hex prefix and stick on a "02" to
          # refer to the root partition.
          default = "PARTUUID=${lib.strings.removePrefix "0x" cfg.firmwarePartitionID}-02";
          description = ''
            Root partition parameter for Linux kernel to be used for
            RaspberryPi boot process.
          '';
        };
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
          description = ''
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
  in lib.mkMerge [ 
    (lib.mkIf isBootloaderRpi   (import ./config-rpiboot.nix { inherit config lib pkgs; }))
    (lib.mkIf isBootloaderUboot (import ./config-uboot.nix   { inherit config lib pkgs; }))
    (lib.mkIf isBootloaderUefi  (import ./config-uefi.nix    { inherit config lib pkgs; }))
    (lib.mkIf cfg.firmware-migration-service.enable
      (import ./firmware-migration-service.nix { inherit config lib pkgs; }))

    {
      boot.kernelParams = {
        uefi = [];
        uboot = [];
        rpi = [
          "root=${cfg.rpi-boot.rootPartition}"
          "rootfstype=ext4"
          "fsck.repair=yes"
          "rootwait"
          "init=/sbin/init"
        ];
      }.${cfg.bootloader};

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
          grub = {
            enable = lib.mkDefault (isBootloaderUefi && !config.boot.loader.systemd-boot.enable);
            device = "nodev";
            efiSupport = true;
          };
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
          # systemd-boot = {
          #   enable = lib.mkDefault isBootloaderUefi;
          # };
        };
      };
      hardware.enableRedistributableFirmware = true;

    }
  ];

}
