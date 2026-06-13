Straight functional mapping — the only trap is Adafruit's silk uses SDI/SDO instead of MOSI/MISO.

| MAX31856 (#3263) | Function | Pi Zero (physical / BCM) |
|---|---|---|
| VIN | Power | **3.3V — pin 1** |
| GND | Ground | GND — pin 6 |
| SCK | Clock | SCLK — pin 23 / BCM11 |
| SDI | Data **into** MAX (= MOSI) | MOSI — pin 19 / BCM10 |
| SDO | Data **out of** MAX (= MISO) | MISO — pin 21 / BCM9 |
| CS | Chip select | CE0 — pin 24 / BCM8 |
| DRDY | Data-ready (optional) | any spare GPIO |
| FLT | Fault, open-drain (optional) | any spare GPIO + pullup |

Key points:

**SDI→MOSI, SDO→MISO** is *not* a crossover — it's the straight by-function mapping. SDI = serial data in *to the chip*, so it takes the Pi's MOSI; SDO = data out *of the chip*, so it feeds the Pi's MISO. The people who miswire this are reading the labels as if they were the Pi's MOSI/MISO silk.

**Power VIN from 3.3V, not 5V.** Pi GPIO is not 5V tolerant. The #3263 has a regulator and level shifting so 5V VIN "works," but feeding it 3.3V guarantees SDO can never present more than 3.3V to the Pi's MISO regardless of what the shifter does. No reason to take the risk on this build.

**SPI mode 1** (CPOL=0, CPHA=1). Whatever reads it — spidev, Klipper's host MCU — has to match or you'll get garbage / CJ faults.

**Enable SPI first** (`dtparam=spi=on`); CE0 enumerates as `spidev0.0`. DRDY/FLT are optional — you can poll instead of wiring them, though FLT to a GPIO is cheap insurance for an unattended heater.

**Noise:** keep these runs short and physically away from the SSR output and the thermocouple leads. Long SPI in a kiln's electrical environment shows up as intermittent CRC/read faults, which on the MAX31856 can masquerade as sensor faults.

One flag: wiring the MAX directly to the Pi's SPI is the RPi-as-linux-MCU path — the one you'd set aside earlier because it collapses the watchdog separation that pushed you toward the Expander/SKR. If this is a deliberate change (or just bench testing the sensor before it goes on a real MCU), carry on. If the kiln-side architecture is still the dedicated-MCU plan, this Pi wiring is only a dev rig, not the final readout path.
