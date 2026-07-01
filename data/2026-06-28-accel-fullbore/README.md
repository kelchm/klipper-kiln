# 2026-06-28 — Accelerated full-bore characterization fire

First high-temperature test fire of the assembled kiln. **Empty chamber**, target cone 6. The goal was not a finished firing but to characterize the kiln — the deliverable ramp-rate-vs-temperature curve, the SSR-heatsink thermal envelope, and control behaviour. Ended on an intentional manual abort at the ~872 °C peak (out of time), followed by a forced cooldown. **Analysis and conclusions live in [`docs/kiln-performance.md`](../../docs/kiln-performance.md)** — this file only describes the raw data.

## Files

- **`accel_run_full.log`** — the authoritative record. 1004 timestamped samples stitched from the live monitor, spanning **138 °C → 872 °C peak → 404 °C** (forced cooldown). One `# MARKER` line marks when the SSR fan was added.
- **`tempstore_snapshot.json`** — a one-time Moonraker `temperature_store` pull (native ~1 Hz, ~20 min window) taken mid-run, for max-fidelity recent data.

## Log format

Space-separated `key=value`; the first field is the epoch timestamp (the Pi clock was ~2 weeks off in AP mode — use it for **deltas only**, not absolute wall time). Fields: `chamber` (°C, MAX31856), `target`/`sp` (heater target / program setpoint), `pow` (SSR duty 0–1), `hs` (SSR heatsink NTC °C), `picpu`/`mcuexp`/`mcumenu` (host + MCU temps), `coil` (contactor 0/1), `state`, `idle` (idle_timeout state).

Two format notes: early samples (throttled-program phase) are at **10 s** spacing and lack the `idle`/`picpu`/`mcuexp`/`mcumenu` columns; later samples are at **2 s** and include them.

## Timeline / discontinuities (important for analysis)

Event chamber-temperatures are read from the log (coil / target transitions):

| Approx chamber | Event |
|---|---|
| 138 °C | Started as `KILN_START_ACCEL` (throttled 300 °C/hr setpoint clock; SSR duty-cycling) |
| ~292 °C | Aborted the program → **manual full bore** (`SET_HEATER_TEMPERATURE TARGET=1220`, SSR pinned 100 %). `KILN_ABORT`'s clean-up reopened the contactor here (`coil` 1→0, re-closed ~322 °C) — the coil-race bug |
| ~502 °C | **Gap:** heater off (`target`→0, contactor stayed closed) — `[idle_timeout]` `TURN_OFF_HEATERS`; caught fast, chamber dipped only ~3 °C |
| ~618 °C | **Gap:** `[idle_timeout]` again (~600 s later) — heater off, chamber fell to ~484 °C before recovery |
| ~819 °C (`ts=1781502672`) | **SSR fan added** (inline `# MARKER`) — heatsink trend reverses from rising to falling |
| ~872 °C | Intentional manual abort (`KILN_ESTOP` — heater + contactor off) |
| 872 → 404 °C | Forced cooldown (lid cracked + focused fan) — **artificial**, not a passive cool curve |

Both heater-off gaps have a re-energize transient right after: the firebrick stayed hot while the element/TC cooled, so the chamber/TC snap back up and **spot rates for ~1–2 min after each restart read falsely high** (~1000–1200 °C/hr apparent). Discard those; use the steady continuous segments. These two gaps are exactly what the `[idle_timeout]` override (`config/kiln.cfg`) and the coil-race fix (`KILN_MANUAL` closing the coil via `KILN_SET_STATE firing`) now prevent.

## Raw observations

For the analysis — deliverable-rate curve, ceiling/feasibility, heatsink envelope — see [`docs/kiln-performance.md`](../../docs/kiln-performance.md). The bare facts from this log:

- **Peak 872.3 °C** at ~116 min of active heating, still climbing ~280 °C/hr when aborted (not a ceiling).
- **Deliverable rate tapers hard** with temperature — steady-segment anchors ~1240 °C/hr @ 325 °C, ~820 @ 475 °C, ~410 @ 775 °C, ~280 @ 872 °C (see the perf-doc MEASURED table for the full curve; ignore the post-restart transients).
- **SSR heatsink** rose with chamber temp (~55 °C @ 500 °C → ~64 °C @ 815 °C) until the fan was added, which dropped it **64 → 48 °C** at full bore and reversed the trend.
- `hs` is the uncalibrated parts-bin NTC (`Generic 3950`) — absolute values are ±several °C.

## The `KILN_START_ACCEL` program (since removed)

`config/programs/accel.cfg` was dropped from the tree after this test (superseded by the menu-driven manual hold). For the record, the run used a 4-segment schedule — rates `[300, 150, 80, 0]` °C/hr → targets `[1100, 1180, 1225, 200]` °C, holds `[0, 0, 600, 0]` s — a fast climb that was abandoned ~292 °C in favour of pinned full bore.
