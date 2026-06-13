# Bench → operational kiln

Path from current state (stub program runner, no real heat) to a kiln
that fires actual schedules. Most of the work is Klipper-side; the
"first 240V" step is a brief checkpoint, not the focus.

## Where we are

- Outputs wired and bench-verified (M0 → SSR, M1 → contactor, manual
  duty cycle confirmed on the bench)
- Heatsink thermistor reads sane
- Display + state machine + neopixels driven by `KILN_SET_STATE`
- Stub runner advances setpoint through ramp+hold but **does not drive
  the SSR** — chamber is a passive observer

The chamber is not actually heated by anything we've built yet.
Everything below is closing that loop.

## 1. Convert SSR to a Klipper heater

Replace `[output_pin ssr]` with `[heater_generic]` so Klipper's
control loop can drive duty. Test macros (`SSR_ON`, `SSR_DUTY`, etc.)
still work via `SET_HEATER_TEMPERATURE` for direct override.

```
[heater_generic kiln]
heater_pin: PA0
max_power: 1.0
sensor_type: MAX31856
sensor_pin: host:gpio8
spi_bus: spidev0.0
tc_type: K
tc_use_50Hz_filter: False
tc_averaging_count: 1
control: watermark   # placeholder; replaced by `pid` after calibration
min_temp: -50
max_temp: 1300
```

Notes:

- `heater_pin: PA0` — same M0/PA0 the bench-test config used. Drop
  the separate `[output_pin ssr]` block at the same time.
- `sensor_type: MAX31856` here means the chamber TC becomes the
  heater's own sensor. The standalone
  `[temperature_sensor kiln_chamber]` block goes away — its readings
  are now available as `printer["heater_generic kiln"].temperature`.
- `control: watermark` (bang-bang) is just a stable default until PID
  calibration runs. Don't fire schedules in watermark mode.

Update the display templates to read from `heater_generic kiln`
instead of `temperature_sensor kiln_chamber`. Same for the watchdog
threshold checks.

## 2. First mains-on (brief)

Goal: prove power flows through the contactor and element under
Klipper's control. ~5 minutes of testing, not 5 hours.

```
COIL_ON                                 # contactor closes
SET_HEATER_TEMPERATURE HEATER=kiln TARGET=80   # 80°C target
```

Watch:

- Chamber temp climbs (any rate at all is fine — proves the loop
  closes)
- Heatsink temp stays bounded — should top out maybe 40-50°C in this
  short test. If it climbs above 60°C in under 5 minutes, SSR
  thermal contact is bad before we even start tuning
- Watchdog stays quiet

```
SET_HEATER_TEMPERATURE HEATER=kiln TARGET=0
COIL_OFF
```

If anything is weird here, stop and debug before moving to PID.
This is a "does the wire path work" check, nothing more.

## 3. PID calibration

Klipper's `PID_CALIBRATE` does the work. Pick a calibration target
that exercises the kiln in its likely operating range — for a Cone 6
fire, calibrate around 1000°C; for low-fire glass, 700°C.

Calibration target reference (start low, recalibrate at higher temps
once you have a baseline):

| Use case | Calibration target |
|---|---|
| Initial sanity | 200°C |
| Low-fire glass | 700°C |
| Bisque / mid-fire | 950°C |
| Cone 6 stoneware | 1200°C |

```
PID_CALIBRATE HEATER=kiln TARGET=200
```

Klipper drives the element through ~3-4 ramp/cool cycles and prints
`Kp`, `Ki`, `Kd` to the log. Plot the cycles in Mainsail; you want
to see clean oscillation with a stable peak-to-peak amplitude.

Issues to watch for during calibration:

- **Asymmetric oscillation** (slow heat-up, fast cool-down or vice
  versa): expected. Kilns lose heat passively much slower than they
  gain it actively. Klipper handles this.
- **Watchdog trips during calibration**: heatsink crossed 80°C
  during sustained heat. Bump the watchdog threshold or fix the
  thermal contact before continuing.
- **Calibration completes but PID values look extreme** (Kp > 100
  or Ki < 0.001): the calibration target was likely too low for the
  kiln's thermal mass. Retry at a higher target.

Save the values:

```
SAVE_CONFIG
```

This persists Kp/Ki/Kd into `printer.cfg`'s `[SAVE_CONFIG]` block.
Klipper restarts; the `control: watermark` line is replaced with
`control: pid` + the calibrated values.

## 4. Validate the PID tuning

Three tests, in order:

### a) Setpoint step response

```
SET_HEATER_TEMPERATURE HEATER=kiln TARGET=500
```

Plot chamber temp in Mainsail. What good looks like:

- Reaches target within 60-90 minutes for a typical hobby kiln
- Overshoots by < 20°C at peak
- Settles within ±2°C of target within 15 minutes after first
  crossing
- No sustained oscillation (small ripple is fine)

If overshoot is > 50°C or oscillation persists > 30 minutes,
recalibrate at the actual target temp.

### b) Holding stability

After step response settles, leave at target for 30 minutes.
Chamber temp should track within ±2°C the whole time. Any drift
beyond ±5°C means PID can't hold against ambient losses → may
need higher Ki.

### c) Slow ramp

Set up a slow ramp via the stub runner (once we wire it to
SET_HEATER_TEMPERATURE):

```
KILN_START_PROGRAM RATE=100 TARGET=500
```

What good looks like: chamber tracks setpoint within ±10°C during
the ramp. If lag is consistently > 20°C, the ramp rate exceeds
what the heater can deliver — that's a kiln physics limit, not a
PID issue. Slow the rate.

## 5. First real firing schedule

A typical bisque schedule (Cone 06 ≈ 1828°F / 998°C, simplified):

| Segment | Rate | Target | Hold |
|---|---|---|---|
| 1 | 100°F/hr | 200°F | 0 (water smoke) |
| 2 | 250°F/hr | 1000°F | 0 |
| 3 | 108°F/hr | 1828°F | 10 min |
| Cool | passive | — | — |

Convert to °C internally for state machine vars.

Things to instrument before running this:

- Cool-down logging — the kiln's passive cool rate tells you what
  ramp rate you can hold during cooling-controlled schedules
- Heatsink temp throughout — establishes the normal operating
  envelope so the watchdog threshold is informed by data, not guess
- Peak chamber temp + time-at-temp logged in `_KILN_STATE.peak_c` and
  whatever elapsed counter we end up using

This is also the first run where the operator should NOT be in
the building unattended. Stay nearby.

## 6. Operational milestones (in order)

After the first successful bisque:

- [ ] PID re-calibrated at the high end of typical operating range
      (≥ 1200°C if you fire Cone 6)
- [ ] Cooling-controlled schedules tested (kiln can hit cooling
      targets, not just ramping ones)
- [ ] Save_variables-backed program library so users can pick from
      multiple schedules in the menu
- [ ] Persistence of `_KILN_STATE` across klippy restarts (currently
      everything resets to idle on reload)
- [ ] Network notification on program complete / fault (Moonraker
      has hooks for this — push notification via ntfy or similar)

After that the controller is operational for routine use.
