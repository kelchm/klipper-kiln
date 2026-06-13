# klipper-kiln

DIY electronic kiln controller built on Klipper firmware, treating the kiln as a single-axis temperature-over-time machine.

## Topology

```
                ┌─────────────────────┐
                │ Pi Zero 2 W (kelchm)│  Klippy + Moonraker + Mainsail + Pi MCU
                │ duncan0             │
                └─────────┬───────────┘
                          │ GPIO 5V + USB
              ┌───────────▼────────────┐
              │ MakerSpot stackable hub │  4× USB-A
              └─┬──────┬───────────────┘
                │      │
        Voron Klipper  STM32_Mini12864
        Expander       adapter
        (F042F6P6)     (F042F6P6)
        ssr + contactor display + encoder + beeper + neopixel
```

- **Pi Zero 2 W** — Klippy + Moonraker + Mainsail. Also runs `klipper-mcu` as a linux-process MCU (planned) to expose `/dev/spidev0.0` for the MAX31856 thermocouple amplifier.
- **Voron Klipper Expander** (STM32F042F6P6) — primary `[mcu]`. 4× 3A MOSFET outputs for the SSR + contactor coil; 2× thermistor inputs (unused on the kiln, which uses a K-type thermocouple via MAX31856 instead).
- **STM32_Mini12864 adapter** (STM32F042F6P6) — `[mcu menu]`, local UI: ST7565 LCD + rotary encoder + click + beeper + neopixel RGBs.

## Hardware

- **MCU shorthand**: both MCUs are the same chip — STM32F042F6P6 in TSSOP20 package. USB peripheral lives on physical pins labeled PA9/PA10 (silicon PA11/PA12 after SYSCFG remap). Firmware build must set `CONFIG_STM32_USB_PA11_PA12_REMAP=y` AND `CONFIG_STM32_FLASH_START_0000=y`.
- **Thermocouple**: Adafruit MAX31856 breakout (Adafruit p/n 3263), K-type, mounted on the Pi's hardware SPI (SPI0, `/dev/spidev0.0`).
- **SSR**: Altran ASR-SI480D40ZW-L. **Contactor**: Omron G7L (physical isolation, watchdog fallback). **Thermal fuse** on kiln body (last-resort hardware layer).

## Layout

```
scripts/
  install-base.sh                # idempotent bring-up: apt deps, klipper user,
                                 # venv, c_helper.so prebuild, systemd unit,
                                 # Moonraker, Mainsail, nginx, persistent journal,
                                 # SPI enable.
  duncan-power-watchdog.sh       # vcgencmd polling every 5s → journald

configs/
  pi/
    printer.cfg                  # main config, includes klipper-mini12864.cfg
    klipper-mini12864.cfg        # Voron sample, kill_pin REMOVED (see below),
                                 # serial paths filled in for our chips
    moonraker.conf               # UDS path corrected, [authorization] block,
                                 # update_manager for klipper/mainsail/moonraker

  systemd/
    klipper.service              # Restart=on-failure + StartLimitBurst=3 to
                                 # avoid OOM-cascade loops
    klipper.env                  # KLIPPER_ARGS pointing at printer_data layout
    duncan-power-watchdog.service
    99-journald-persistent.conf  # overrides RPi's 40-rpi-volatile-storage.conf
                                 # — without this, journald writes to tmpfs and
                                 # crash logs vaporize on reboot

  nginx/
    mainsail.conf                # /etc/nginx/sites-available/mainsail

firmware/
  stm32f042f6p6.kconfig          # Klipper .config for BOTH MCUs (Expander and
                                 # Mini12864 adapter use the same chip family).
                                 # See FIRMWARE.md for build/flash steps.
```

## Bring-up on a fresh Pi

1. Flash Raspberry Pi OS Lite 64-bit (Trixie) via Imager. Hostname `duncan0`, user `kelchm`, SSH key from 1Password agent.
2. Establish passwordless sudo (one-time, persistent):
   ```
   ssh -t kelchm@duncan0 'echo "kelchm ALL=(ALL) NOPASSWD:ALL" | sudo tee /etc/sudoers.d/010-kelchm-nopasswd >/dev/null && sudo chmod 440 /etc/sudoers.d/010-kelchm-nopasswd'
   ```
3. Run the base install:
   ```
   scp scripts/install-base.sh kelchm@duncan0:/tmp/
   ssh kelchm@duncan0 'bash /tmp/install-base.sh'
   ```
4. The MCUs ship with the v0.13.0 Klipper firmware we built; nothing to flash unless they're virgin chips. If they need flashing, see `firmware/` for the `.kconfig` and build steps.
5. Drop the captured `printer.cfg` + `klipper-mini12864.cfg` into `/home/klipper/printer_data/config/`. Update USB serial numbers if you swap MCUs.
6. `sudo systemctl restart klipper` — klippy should reach `state: ready`.

## Gotchas (collected the hard way)

- **`kill_pin: !menu:PF0` in the upstream Voron `klipper-mini12864.cfg` MUST be removed** before first klippy start. The sample ships without a pull-up; PF0 floats and klippy reads it as "kill button pressed", sends firmware shutdown to BOTH MCUs, and then can't recover without physical RESET on each. Our captured version has it removed.
- **Pi Zero 2 W ships with the legacy 2012 `dwc_otg` USB driver by default** on Trixie. Under sustained Klipper USB traffic it wedges with `urb_dequeue: Timed out waiting for FSM NP transfer to complete` and eventually hangs the kernel. **Fix is one line**: add `dtoverlay=dwc2,dr_mode=host` to `/boot/firmware/config.txt` in the `[all]` section. The image ships this overlay under `[cm5]` only (Compute Module 5), so Pi Zero 2 W has to be added explicitly. After the change, `lsusb -t` shows devices `using dwc2`. Our `install-base.sh` does this automatically.
- **Procedural rule for clearing MCU firmware shutdown**: ALWAYS `sudo systemctl stop klipper` before pressing the physical RESET button(s) on the MCUs. Resetting MCUs while klippy is running causes klippy to retry-loop, which floods USB and can still wedge things even on `dwc2`. Sequence: stop klipper → reset MCUs → start klipper.
- **For the MAX31856 (and any other software-CS SPI peripheral on the host MCU)**: replace `dtparam=spi=on` with `dtoverlay=spi0-0cs`. The default reserves BCM 7/8 (CE0/CE1) as kernel-managed chip selects, so Klipper can't toggle them as software CS pins.
- **Don't run `echo 0 > /sys/bus/usb/devices/1-1/authorized`** to try to reset a single port. `1-1` is the hub itself, not a port — this unauthorizes the whole bus and the USB controller may not enumerate again until reboot.
- **WiFi power-save defaults to ON on Pi Zero 2 W's brcmfmac driver**, adding 50-100 ms latency to every interactive packet (visible as laggy SSH typing and sluggish Mainsail). Our `install-base.sh` disables it via `nmcli connection modify <conn> 802-11-wireless.powersave 2`; if you skip the installer, run that yourself.
- **Trixie defaults to volatile journald storage** (`/usr/lib/systemd/journald.conf.d/40-rpi-volatile-storage.conf`). Without our `99-journald-persistent.conf` drop-in, `journalctl --boot=-1` will return nothing after every crash. The drop-in also forces creation of `/var/log/journal/<machine-id>/`.
- **Klipper firmware for the F042F6 overflows the 32 KB flash** with default `WANT_*` options enabled. The `WANT_*=n` settings in our kconfig trim ~8 KB worth of accelerometer/load-cell/legacy-display features we don't need.
- **`make clean` removes both `out/` and `.config`** in newer Klipper — keep a copy of your `.config` somewhere safe (see `firmware/stm32f042f6p6.kconfig`).
