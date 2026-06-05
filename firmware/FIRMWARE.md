# MCU firmware (STM32F042F6P6)

Both the Voron Klipper Expander and the STM32_Mini12864 adapter use the **STM32F042F6P6** (TSSOP20, 32 KB flash, 6 KB SRAM, USB FS native). Same kconfig works for both.

## Build

On the Pi (or any Linux box with `arm-none-eabi-gcc` and Python 3):

```bash
cd ~/klipper
git checkout v0.13.0                            # pin to stable
cp /path/to/stm32f042f6p6.kconfig .config
make clean
make olddefconfig
make -j2
arm-none-eabi-objdump -h out/klipper.elf | grep .text   # verify VMA = 0x08000000
```

Expected size: ~27.5 KB (fits 32 KB with ~4 KB headroom). If you see `region 'rom' overflowed`, an upstream change added bloat — disable more `WANT_*` flags in `.config`.

## Critical kconfig settings

These are non-obvious traps documented in the project memory:

- `CONFIG_STM32_USB_PA11_PA12_REMAP=y` — TSSOP20 package bonds USB pins as `PA9/PA10`; SYSCFG remap is required. Without this, USB silently doesn't enumerate and the chip *appears dead* after flash.
- `CONFIG_STM32_FLASH_START_0000=y` — kconfig's default is `_2000` (assumes 8 KB bootloader). DFU flashes go to `0x08000000`, so binary must be linked for that address. Without this, flash succeeds but the reset vector points 8 KB into garbage and the chip silently hangs.
- `CONFIG_STM32_CLOCK_REF_INTERNAL=y` — board has no external crystal (PF1 is used as GPIO for beeper).

## Flash via DFU

1. Plug only the target MCU into the hub.
2. Put it into DFU mode:
   - **Klipper Expander**: hold BOOT, tap RESET, release BOOT.
   - **Mini12864 STM32 adapter**: install the BOOT0 jumper, power-cycle, then remove jumper.
3. Verify DFU device visible: `sudo dfu-util -l` should show `Found DFU: [0483:df11]`.
4. Flash:
   ```bash
   sudo dfu-util -a 0 -d 0483:df11 -s 0x08000000 -D out/klipper.bin
   ```
   The trailing `dfu-util: Error during download get_status` is cosmetic if `:leave` is appended; omit `:leave` and press RESET manually for a cleaner sequence.
5. Press RESET (with no BOOT pressed/jumpered). Within 1–2 seconds the device should re-enumerate as `/dev/serial/by-id/usb-Klipper_stm32f042x6_<chipid>-if00`.

## Known chip IDs (this build)

| Device                     | USB serial (chipid)         | Hub port |
|----------------------------|------------------------------|----------|
| Voron Klipper Expander     | `240005000143534133343520`  | 1-1.2    |
| STM32_Mini12864 adapter    | `260023001243535031303120`  | 1-1.3    |

The chipid is the STM32's factory-burned 96-bit unique ID, formatted by Klipper firmware. Persists across reflashes. Used in printer.cfg `[mcu]` blocks as the `serial:` by-id path so device ordering doesn't matter.
