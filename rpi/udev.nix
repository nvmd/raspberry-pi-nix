{ config, lib, pkgs, ... }:

{
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
}