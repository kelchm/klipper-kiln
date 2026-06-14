# Kiln Programs

Five programs are available from the encoder menu under **Start firing**.
All temperatures in °F. Bisque assumes vent open during burnout.
A `↓` next to a rate means the setpoint *descends* during that segment
(drop-and-hold or controlled cool); the heater modulates downward at that rate.
All other rates ramp the setpoint upward.

---

## Bisque ^06

**~24 h active, ~32 h door-closed.** Adapted from Plainsman BQ1000 with slower
ramps through carbon burnout and quartz inversion for thick / hand-built work.
Suitable for all four clays (112, 240, 240G, 420). Required before any glaze
firing if using Kiwi underglaze.

| Step | Rate | Target | Hold |
|---|---|---|---|
| 1 | 60°F/hr | 200°F | 6 h |
| 2 | 80°F/hr | 600°F | — |
| 3 | 100°F/hr | 1100°F | — |
| 4 | 150°F/hr | 1700°F | — |
| 5 | 108°F/hr | 1828°F | 30 min |

Run room ventilation if 112 Brown is in the load.

---

## Glaze ^5 Bright

**~10 h active, ~20 h door-closed.** Plainsman C04PLTP drop-and-hold with peak
adjusted from cone 04 to cone 5. Use when Kiwi underglaze color matters or
when working with 112 Brown (best surface at cone 5). 240/240G will be slightly
under-vitrified at this cone — fine for decorative pieces, not for functional
ware needing water-tightness.

| Step | Rate | Target | Hold |
|---|---|---|---|
| 1 | 100°F/hr | 250°F | 1 h |
| 2 | 350°F/hr | 2050°F | — |
| 3 | 100°F/hr | 2135°F | 10 min |
| 4 | 900°F/hr ↓ | 2050°F | 30 min |

---

## Glaze ^6 Durable

**~10 h active, ~22 h door-closed.** Plainsman PLC6DS unchanged. Full
vitrification on 240 / 240G white throwing bodies — use for functional ware.

| Step | Rate | Target | Hold |
|---|---|---|---|
| 1 | 108°F/hr | 250°F | 1 h |
| 2 | 350°F/hr | 2100°F | — |
| 3 | 108°F/hr | 2200°F | 10 min |
| 4 | 900°F/hr ↓ | 2100°F | 30 min |

---

## Glaze ^6 SlowCool

**~15 h active, ~22 h door-closed.** Plainsman C6DHSC. Same peak as Durable
plus a controlled cool from 2100°F → 1400°F at 150°F/hr (the heater stays
active and modulates the cooling rate). Use for matte or reactive glazes where
crystal development during cooling drives the surface.

| Step | Rate | Target | Hold |
|---|---|---|---|
| 1 | 108°F/hr | 250°F | 1 h |
| 2 | 350°F/hr | 2100°F | 15 min |
| 3 | 108°F/hr | 2200°F | 10 min |
| 4 | 900°F/hr ↓ | 2100°F | 30 min |
| 5 | 150°F/hr ↓ | 1400°F | — |

---

## Test

**~1 min.** Four-segment controller exercise, peak ~40°C. Safe to run with
the contactor closed.

---

## Operating

**Start:** encoder → **Start firing** → program → press.

**Abort:** encoder → **Abort program** → press. Three beeps, white LED flash,
heater off, contactor opens, returns to IDLE in ~2 s. Restart possible immediately.

**Acknowledge complete:** encoder → **Acknowledge / reset** when the kiln shows
COMPLETE (bright green LEDs).

**Faults** (red LEDs) display the cause. Clear from the encoder menu only after
understanding the cause:

- *Chamber TC invalid* — broken / loose thermocouple wire.
- *Chamber overtemp* — > 1250°C; investigate before next firing.
- *SSR heatsink overheat* — > 80°C; let it cool, check fan if installed.
