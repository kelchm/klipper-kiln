# Kiln performance — preliminary characterization

*Source: 2026-06-28 accelerated full-bore test fire (`data/2026-06-28-accel-fullbore/`). Empty chamber, ~116 min active heating, **peaked 872 °C** (full power / SSR pinned 100 % above ~290 °C). Cone-6 temperatures were not reached — everything above 872 °C is inferred, labelled accordingly. Numbers refined against an energy-balance model and known kiln engineering. "As we understand it so far."*

## Bottom line

Cold, the kiln ramps very fast (~1240 °C/hr at 325 °C); the rate falls steeply to ~280 °C/hr at the 872 °C peak. The taper is **rising heat loss**, not a weakening element (element power is ~constant, ~3.55 kW hot).

**Cone 6 is right at the edge of this kiln's capability — neither clearly reachable nor clearly out of reach.** The modelled steady-state ceiling sits at ~1186–1260 °C; cone 6 (1220 °C) lands inside that band. Whether it gets there is decided by two things we have *not* measured: the **insulating-brick conductivity** (k ≤ ~0.25 W/m·K → reaches cone 6 as a slow crawl; worse → stalls ~1100–1170 °C) and the **element's actual hot power**. The cone-4 rating is self-consistent with this: it implies k ≈ 0.25 and a ceiling right around cone 6.

Two caveats sharpen it: a **loaded** kiln is slower and runs hotter (worse on both counts), and the **SSR heatsink** independently reaches its 80 °C watchdog around cone-6 temperature unless fan-cooled. **The cheap, decisive test is a constant-temperature hold (below), not another ramp.** Note the fast climb at 872 °C does *not* indicate top-end headroom — see Physics.

## Chamber & power

- **Interior:** ~15″ across (heptagonal) × ~18″ deep, **2.5″ IFB wall** → **~1.6–1.8 cu ft**, interior surface ≈ **0.78 m² (8.3 ft²)**.
- **Element:** 240 V, 15.3 Ω cold → 3765 W cold; **~3.55 kW hot** (NiCr/Kanthal resistance rises ~4–7 % hot — use the hot figure).
- **Watt density:** ~1.93 kW/cu ft hot. (Looks fine next to a cone-10 Skutt 1027 at 1.64 kW/cu ft — but W/cu ft flatters small kilns, which lose heat by *surface area*. The direct loss balance below is what counts.)

## Deliverable ramp rate vs. temperature (empty, full power)

### MEASURED — 325–872 °C (hard data)

| Chamber | Rate | confidence |
|---|---|---|
| 325 °C | ~1240 °C/hr | high |
| 425 °C | ~1015 °C/hr | high |
| 475 °C | ~820 °C/hr | high |
| 575 °C | ~750 °C/hr | low (interruption band) |
| 625 °C | ~600 °C/hr | low (interruption band) |
| 775 °C | ~410 °C/hr | high |
| 825 °C | ~360 °C/hr | high |
| 872 °C | ~280 °C/hr | high — **highest point reached; still climbing, NOT a ceiling** |

Interpolate between anchors (monotone); no high-res data 650–740 °C (logging gap). ~4.5× drop from 325 → 872 °C.

### INFERRED — above 872 °C

No measured data. The rate continues into a tens-of-°C/hr crawl as it nears the ceiling. The ceiling itself depends on brick conductivity (2.5″ wall, `ceiling = T_amb + P·t/(k·A)`):

| brick k (W/m·K) | steady ceiling | |
|---|---|---|
| 0.22 | ~1370 °C | clears cone 6 |
| 0.24 | ~1260 °C | clears cone 6 |
| **0.25** | **~1215 °C** | **right at cone 6** |
| 0.26 | ~1170 °C | cone 4, stalls short |
| 0.30 | ~1020 °C | well short |

Cone 6 needs **k ≤ 0.249**; cone 4 needs k ≤ 0.256 — a hair apart. K-23 firebrick runs ~0.24–0.27 at the relevant mean wall temperature → **right on the line.**

### Where real schedules outrun the element (chamber lags setpoint → lag-warning fires)

Repo schedule rates vs. the deliverable curve (lag onset is uncertain in the same band as the ceiling above):

| Schedule rate | Segment → target | Lag onset | Status |
|---|---|---|---|
| 33–83 °C/hr | bisque ramps → ≤ 998 °C | ~993 °C or never | bisque (cone 06, 998 °C) reaches temp |
| **194 °C/hr** | glaze main climb → 1121/1149 °C | **~910–985 °C** | **confirmed lag zone:** top ~140–235 °C runs slower than commanded |
| 60 °C/hr | glaze cone-6 final 1149 → 1204 °C | **~990–1180 °C** | **power-marginal:** crawls/lags the final stretch, or stalls short if brick/element are on the bad side |

The runner is open-loop on rate (it ramps the setpoint regardless of chamber keep-up), so above the crossover the chamber-vs-setpoint error grows and the lag indicator trips — the correct instrument for these zones. See `[[project_runner_soak_keys_setpoint]]`. **The upper third of the glaze schedules over-asks for this element.**

## Physics (why the taper, why the fast climb is misleading, why no clean answer)

Energy balance during a ramp: `rate = (P_element − P_loss(T)) / C_eff`.

- **Element ≈ constant power** (~3.55 kW hot; TCR only 4–7 %). The taper is **rising loss**, not falling power.
- **`C_eff ≈ 7.8 kJ/°C`** is the *fast* effective ramp mass (~7–10 kg of inner-face brick + furniture), not the kiln's total heat capacity.
- **The fast climb does not mean top-end headroom.** At 872 °C, of the 3.55 kW going in, only **~0.6 kW raises the chamber** (the 280 °C/hr), ~0.6 kW is real loss, and **~2.3 kW is banked in the cold outer brick.** That stored heat is *borrowed* — it makes a cold-walled kiln climb fast, and it converts to loss as the walls charge near the top. So 280 °C/hr at 872 °C is consistent with a true ceiling anywhere from ~1050 °C to ~1370 °C — it tells us the ceiling is well above 872 °C, not whether it clears cone 6.
- **The earlier "~1024 °C hard ceiling" was a single-node fitting artifact** — a one-capacitance model fitting a fast ramp mislabels wall *storage* as ambient *loss*, inflating the apparent loss coefficient (~3.7 W/°C apparent vs. ~2.6–3.1 W/°C true) and dragging the rate-vs-T line to a false zero. There is no hard wall there; the rate flattens into a crawl and keeps climbing.
- **Why no clean answer from this run:** a single full-power ramp cannot separate `C_eff` from steady loss (the wall is still charging), and the conduction/radiation loss split is ill-conditioned over 325–872 °C. The ceiling genuinely straddles cone 6.

## SSR heatsink thermal envelope

- Pre-fan, the heatsink tracked **chamber temperature** at ~3.8–4.3 °C per 100 °C (enclosure soak-up, partly a *time* effect → a slower fire may run it hotter at a given chamber temp). Linear extrapolation puts the **80 °C watchdog right around cone 6**, no usable margin (convex steepening near the top + uncalibrated NTC ±several °C → could trip at or just below cone 6; a transient could trip it sooner).
- **Fan:** dropped the heatsink ~16 °C at full bore (64 → 48 °C) and reversed the rising trend. Needed to keep the SSR in-envelope at high temperature.
- Host/MCU temps comfortable (Pi CPU 47–54 °C, Expander MCU 46–52 °C) but warming with the fire.

## Control behaviour

Watermark bang-bang (`max_delta 0.5 °C`) held the chamber within −1.7 / +1.1 °C of a 300 °C/hr setpoint at only ~35 % SSR duty (140–290 °C) — large low-temp headroom; watermark is fully adequate for rate-limited ramps where the requested rate is below the deliverable curve. PID's only potential value is high-temp holds, untested.

## Not established (MEASURED vs INFERRED vs UNKNOWN)

- **True maximum temperature — UNKNOWN, straddles cone 6.** Modelled band ~1186–1260 °C, decided by brick conductivity (≈ k 0.25) and element power.
- **Brick conductivity k — UNKNOWN.** The single most leveraged parameter; k ≤ 0.249 → cone 6, k ≥ 0.26 → stalls short.
- **Element hot power — UNKNOWN and decisive.** ~3.4–3.5 kW hot is consistent with in-spec *or* a mildly aged/oxidized element; if it has crept down, the cone-6 crawl becomes a stall.
- **Loss-curve shape > 872 °C — UNKNOWN.** Loaded behaviour, passive cool rate, heat-work/cone calibration, chamber uniformity (single TC), heatsink-NTC absolute accuracy — all uncharacterized.

## Recommended next measurements (cheap → decisive, in order)

1. **Constant-temperature holds at ~1000 °C and ~1100 °C** — log the average SSR duty; `duty × 3.55 kW` = the *true* steady-state loss at that temperature (no storage to confuse it). Two of these fix the loss curve and hence the ceiling directly. **An hour of holding answers what no ramp can.**
2. **Hot element resistance / power** — measure current at temperature; settles whether the element is in-spec.
3. **A loaded, fan-cooled, NTC-calibrated fire toward cone 6** with witness cones top + bottom — feasibility under load, heat-work offset, passive cool curve.
4. **Revisit the glaze schedules' top third** — the 194 °C/hr main climb and 60 °C/hr cone-6 approach exceed deliverable capacity above ~900–990 °C; accept the lag/longer time or lower the rates to match.
