# Comprehensive Review — klipper-kiln

> Source-of-truth record for the safety / architecture / code-quality / documentation
> review. Each finding below has a stable ID (`S#`, `A#`, `Q#`, `D#`) and is intended
> to map 1:1 to a tracked GitHub issue. The tracking issue links back here.

**Scope reviewed:** all of `config/`, `pi/`, `scripts/`, `firmware/`, `tools/`, and
`docs/` at branch `claude/repo-comprehensive-review-wqc2lt`.

**Context that sets the bar:** this is an unattended, mains-powered, ~1300 °C heat
source. Findings are weighted toward safety accordingly, but severities are kept
honest — see the equilibrium correction in S1.

---

## Index

| ID | Title | Area | Severity | Blocks unattended firing? |
|----|-------|------|----------|---------------------------|
| S1 | Over-temp protection shares the single control thermocouple | safety | medium | decision |
| S2 | Contactor stays energized during passive cool-wait | safety | medium | ✅ |
| S3 | Watchdog/runner can silently die — no liveness supervision | safety | high | ✅ |
| S4 | SSR heatsink over-temp trip rides on an uncalibrated sensor curve | safety | high | ✅ |
| S5 | Unauthenticated LAN/AP control of the mains heater | safety | medium | — |
| S6 | As-shipped control mode (`watermark`) is the one the runbook says not to fire in | safety | low | — |
| A1 | Safety-critical thermocouple lives on the host (Pi) MCU | architecture | medium | — |
| A2 | No state persistence / firing not resumed across klippy restart | architecture | medium | — |
| Q1 | Validate program segment lists at start | code-quality | medium | — |
| Q2 | Name safety thresholds as constants / single source of truth | code-quality | low | — |
| Q3 | `KILN_FAULT` should explicitly cancel the runner | code-quality | low | — |
| D1 | `first-power-runbook.md` is stale: control loop is already closed | docs | high | ✅ |
| D2 | Add `SAFETY.md` (safety model + single points of failure) | docs | medium | — |
| D3 | Docs & cleanup nits (stale "planned" MCU, LICENSE, slow-cool wording, M300 edge) | docs | low | — |

**"Before unattended firing" milestone:** S1 (decision), S2, S3, S4, D1.

**Cross-links:** S1 ↔ A1 (TC topology) · S3 ↔ Q1 (validation removes the likeliest
runner throw) ↔ S4 (heatsink is the real electrical-stress monitor) · A2 is the
restart half of S3's reliability story.

---

## Safety

### S1 — Over-temp protection shares the single control thermocouple
**Severity:** medium · **Gating:** design decision

**Summary.** The soft over-temp watchdog reads the *same* thermocouple the control
loop steers on, so a sensor that reads falsely low blinds both at once.

**Context.** `_KILN_FAULT_WATCHDOG` reads `printer["heater_generic kiln"].temperature`
(`config/safety.cfg:45`) — identical to the value the PID/watermark loop uses
(`config/outputs.cfg:25-40`). There is no temperature path independent of the
control sensor.

**Failure mode / impact.** A TC that reads low (junction short, connector corrosion
forming a parasitic cold junction, tip slipping out of the chamber) makes the loop
drive full power while the watchdog — seeing the same low value — never crosses its
`>1250 °C` trip.

**Honest bound (correction from initial review).** This is **not** thermal runaway.
A resistive element on fixed mains is a roughly constant-power source; the chamber
asymptotes to the temperature where loss equals input. Kanthal/NiCr elements have a
slightly *positive* temperature coefficient (power falls as they heat) — negative
feedback, self-limiting. The realistic harm is therefore **over-firing the load to
the element's full-power equilibrium**: ruined ware, and molten glaze running onto
shelves/element (the genuine fire-adjacent scenario), plus sustained max electrical
draw on the SSR/contactor/wiring. Whether equilibrium is *dangerous* depends on
whether the element is sized so its full-power asymptote sits below the kiln's
brick/element rating — a hardware property the controller can't verify.

**Existing backstops.**
- `verify_heater max_error: 250` (`config/safety.cfg:26-30`) catches a *gross* low
  read (setpoint 1200, TC 200 → error 1000 > 250 → MCU shutdown), but **not** a bias
  of ≤250 °C, which silently over-fires.
- Hardware thermal fuse on the kiln body (README) — the real independent last line,
  outside this repo.

**Proposed fix.**
- Add an over-temperature cutout that does *not* share the control TC (independent
  limit TC + comparator, or a mechanical high-limit) — standard commercial-kiln
  practice.
- At minimum, treat the body thermal fuse as a load-bearing safety control: document
  its rating, verify it is installed, and state in writing "do not fire unattended
  without it."
- Capture the element's full-power equilibrium temperature relative to the kiln's
  rating; if it asymptotes near/above the rating, the independent-cutout argument
  keeps teeth.

**References.** `config/safety.cfg:45`, `config/safety.cfg:26-30`,
`config/outputs.cfg:25-40` · related: A1.

---

### S2 — Contactor stays energized during passive cool-wait
**Severity:** medium · **Gating:** ✅ before unattended firing

**Summary.** Mains is held live at the SSR input during the long, unattended,
zero-heat cool-wait phase, removing the stuck-SSR isolation exactly when it is most
wanted.

**Context.** The series contactor is the defense against the SSR's dangerous failure
mode (SSRs fail *shorted* — stuck on). `KILN_SET_STATE` closes the coil for
`['firing','holding','cooling']` and opens it otherwise
(`config/state-machine.cfg:73-77`). But `state='cooling'` is *only* the passive
cool-wait segment (rate == 0), where the heater target is forced to 0
(`config/program-runner.cfg:121-123`). Active controlled-cooling (descending ramp,
heater modulating) runs as `state='firing'`, not `cooling`.

**Failure mode / impact.** During cool-wait — potentially many hours, unattended,
zero heat intended — the contactor stays closed. If the SSR is stuck shorted, that's
precisely the window where mains should be physically open and isn't.

**Existing backstops.** Hard `max_temp` + watchdog would eventually trip on the
resulting reheat, but the whole point of the contactor is to not depend on that.

**Proposed fix.** Open the contactor for `cooling` too — change the gate to
`{% if s in ['firing','holding'] %}`. Active cool is already `firing`, so controlled
cooling still keeps the contactor closed; passive cool-wait correctly drops mains.
One-line change; if a program later advances from cool-wait into another heated
segment, `KILN_SET_STATE firing` re-closes it.

**References.** `config/state-machine.cfg:73-77`, `config/program-runner.cfg:121-123`.

---

### S3 — Watchdog/runner can silently die — no liveness supervision
**Severity:** high · **Gating:** ✅ before unattended firing

**Summary.** Both self-rescheduling loops re-arm at the *bottom* of their body, so a
single exception in any tick permanently kills the loop with no alarm.

**Context.** `_KILN_FAULT_WATCHDOG` re-arms at `config/safety.cfg:57`; `_KILN_RUNNER`
re-arms at `config/program-runner.cfg:159-161`. A Klipper `gcode:` template is
**rendered atomically to a string, then executed**, which creates two failure
surfaces:
1. **Execution-time** — a rendered command fails at runtime.
2. **Render-time** — the Jinja template raises while rendering (e.g.,
   `segment_rates_c_per_hr[step-1]` indexing a malformed program list,
   `config/program-runner.cfg:74`). No command in the block runs — re-arm included.

Because render is atomic, simply moving the re-arm to the top of the *same* macro
only protects surface (1), not (2) — and (2) (a bad list index) is the most likely
way the runner dies.

**Failure mode / impact.**
- Dead **watchdog** → loses the soft over-temp / heatsink / TC-invalid trips.
- Dead **runner** → setpoint frozen at its last value; if that is peak, the kiln
  holds at cone temperature indefinitely (over-fires the load). `verify_heater`
  won't fire on a setpoint it is tracking fine.

**Existing backstops.** Klipper-native `verify_heater` and the hard `min/max_temp`
limits run independently of these loops and catch the catastrophic end (see Fix 2).

**Proposed fix (layered).**

*Fix 1 — bulletproof re-arm via a tick/work split.* Isolate the re-arm into a
trivial template that cannot fail to render; put all fallible logic behind a separate
macro call invoked afterward.

```ini
[delayed_gcode _KILN_FAULT_WATCHDOG]
initial_duration: 5
gcode:
    UPDATE_DELAYED_GCODE ID=_KILN_FAULT_WATCHDOG DURATION=5
    _KILN_FAULT_CHECK          # all sensor reads / comparisons live here

[delayed_gcode _KILN_RUNNER]
gcode:
    {% set st = printer["gcode_macro _KILN_STATE"].state %}
    {% if st in ['firing','holding','cooling'] %}
        UPDATE_DELAYED_GCODE ID=_KILN_RUNNER DURATION=1
    {% endif %}
    _KILN_RUNNER_WORK          # current body minus its bottom reschedule
```

Reading `state` is always safe to render, so the runner tick re-arms only while
active (stops cleanly at terminal states) and a worker throw can no longer kill the
loop. The `DURATION=0` cancel idiom is already proven at `config/program-runner.cfg:167`.

*Fix 2 — don't depend on the soft loops for catastrophic trips.* Ensure every soft
trip has a Klipper-native hard backstop so a dead watchdog is non-critical:
- Chamber overtemp: soft 1250 (`config/safety.cfg:49`) backstopped by hard
  `max_temp: 1300` (`config/outputs.cfg:40`); consider tightening to ~1280.
- TC open: already hard-backstopped by the MAX31856 driver's fault-register check.
- Heatsink: soft 80 (`config/safety.cfg:53`) vs hard 150 (`config/sensors.cfg:15`) —
  too far; lower the hard limit (see S4).

*Fix 3 — mutual liveness.* Runner increments a `runner_heartbeat` var each tick; the
watchdog faults (`Runner stalled`) if state is active but the heartbeat hasn't
advanced since the previous 5 s tick. Seed last-seen at program start to avoid a
false stall.

*Fix 4 — remove the likeliest throw at the source.* See Q1 (validate program lists
at start).

*Fix 5 — make a death visible.* Stamp `watchdog_last_run` each tick and surface it on
the tech screen; wire the planned Moonraker notification so a tripped *or* stale loop
reaches the operator off-site. Most robust (heaviest): an external poller (systemd
timer / Moonraker component) that calls `KILN_ESTOP` via the API on active-but-stale.

**Recommended minimum:** Fix 1 + Fix 2 + Fix 4. Add Fix 3 for the frozen-hold case
and Fix 5 for visibility.

**References.** `config/safety.cfg:42-57`, `config/program-runner.cfg:61-161`,
`config/program-runner.cfg:167` · related: Q1, S4.

---

### S4 — SSR heatsink over-temp trip rides on an uncalibrated sensor curve
**Severity:** high · **Gating:** ✅ before unattended firing

**Summary.** The heatsink over-temp protection — the monitor on the component most
stressed by sustained full power — depends on a guessed thermistor curve.

**Context.** `config/sensors.cfg:9-15`: *"Unmarked NTC from the parts bin … beta
unknown. Generic 3950 is a reasonable starting curve."* Both the `>80 °C` soft trip
(`config/safety.cfg:53`) and the `150 °C` hard limit depend on it.

**Failure mode / impact.** SSR thermal runaway (stuck-on → heatsink climbs) is a real
fire path. An uncalibrated curve could trip at actual 60 °C (nuisance) or actual
110 °C (too late). Note S1's correction makes this *more* important, not less:
sustained full-power equilibrium concentrates risk on the electrical side, and this
is the sensor watching it.

**Proposed fix.** Calibrate against a known reference (ice point + a thermometer at
operating range), record the resulting curve/`beta`, and lower the hard `max_temp`
toward ~95-100 °C so a dead soft-watchdog still gets a hard trip well before danger.

**References.** `config/sensors.cfg:9-15`, `config/safety.cfg:53`,
`config/outputs.cfg` (heater hard limits) · related: S3 Fix 2.

---

### S5 — Unauthenticated LAN/AP control of the mains heater
**Severity:** medium · **Gating:** —

**Summary.** Anyone on the LAN — or in RF range of the AP, if open — can issue gcode
and energize the element with no authentication.

**Context.** `config/moonraker.conf:14-15` sets `force_logins: False`, and
`trusted_clients` covers all of RFC1918 (`10/8`, `172.16/12`, `192.168/16`)
(`config/moonraker.conf:23-29`). AP mode hosts a `kiln` SSID (`config/network.cfg`).
The same authorization block is re-emitted by the installer
(`scripts/install-base.sh:143-176`).

**Failure mode / impact.** `SET_HEATER_TEMPERATURE` / `COIL_ON` are reachable without
auth from any trusted client; remote actuation of a mains heater.

**Proposed fix.** Require auth (at least in AP mode), ensure the `kiln` AP is
WPA2-protected, and narrow `trusted_clients` to the actual subnet rather than all
RFC1918.

**References.** `config/moonraker.conf:14-29`, `config/network.cfg`,
`scripts/install-base.sh:143-176`.

---

### S6 — As-shipped control mode is the one the runbook says not to fire in
**Severity:** low · **Gating:** —

**Summary.** The deployed default is `control: watermark`, which the runbook
explicitly says not to fire schedules in.

**Context.** `config/outputs.cfg:35` ships `watermark` with `max_delta: 0.5` (PID
lands later via `SAVE_CONFIG`); `docs/first-power-runbook.md:48-49` says *"Don't fire
schedules in watermark mode."*

**Failure mode / impact.** Bang-bang on high thermal mass = large overshoot; bounded
by the 1250/1300 limits but over-fires ware and contradicts the documented procedure.

**Proposed fix.** Add a louder warning that the deployed default is not fire-ready;
optionally an interlock that refuses to start a program while uncalibrated (e.g., a
sentinel variable set by the PID-calibration step).

**References.** `config/outputs.cfg:35`, `docs/first-power-runbook.md:48-49`.

---

## Architecture

### A1 — Safety-critical thermocouple lives on the host (Pi) MCU
**Severity:** medium · **Gating:** —

**Summary.** The single most safety-critical input is read by the least real-time,
most memory-pressured node.

**Context.** The chamber TC is read via the Pi linux-process MCU
(`config/kiln.cfg:15-16`, `config/outputs.cfg:30-31`), not the dedicated STM32
Expander. The Pi simultaneously runs nginx + Moonraker + Mainsail + WiFi on 512 MB;
the entire README/installer is engineered around avoiding OOM (prebuild
`c_helper.so`, start klipper last, `StartLimitBurst=3`). `docs/MAX31856-wiring.md:26`
itself flags that this topology "collapses the watchdog separation that pushed you
toward the Expander/SKR."

**Failure mode / impact.** A host-MCU stall (OOM is realistic here) loses the TC
reading. Klipper detects host-MCU comms timeout → shutdown (fail-safe), but it ties
the safety-critical sensor to the busiest node, and a restart abandons the firing
(A2).

**Proposed fix.** Move the TC onto the dedicated MCU, or document the deliberate
acceptance of host-MCU sensing with the OOM-mitigation measures as load-bearing.

**References.** `config/kiln.cfg:15-16`, `config/outputs.cfg:30-31`,
`docs/MAX31856-wiring.md:26` · related: S1, A2.

---

### A2 — No state persistence / firing not resumed across klippy restart
**Severity:** medium · **Gating:** —

**Summary.** A transient klippy restart mid-fire silently abandons the firing.

**Context.** All `_KILN_STATE` variables reset to defaults on reload
(`config/state-machine.cfg:26-40`); acknowledged as a TODO in
`docs/first-power-runbook.md:202-204`. systemd `Restart=on-failure`
(`pi/systemd/klipper.service:20`) brings klippy back to idle.

**Failure mode / impact.** Fail-safe (contactor `value: 0` / `shutdown_value: 0` opens
mains, heater target resets to 0 — `config/outputs.cfg:46-49`), so the kiln cools;
but a single transient restart aborts an unattended multi-hour firing with no
resumption.

**Proposed fix.** Persist `_KILN_STATE` (e.g., `save_variables`) and add a
guarded resume path, or — at minimum — an explicit, loud "firing was interrupted"
indication on restart so the operator isn't misled by a silent idle screen.

**References.** `config/state-machine.cfg:26-40`, `docs/first-power-runbook.md:202-204`,
`pi/systemd/klipper.service:20`, `config/outputs.cfg:46-49`.

---

## Code quality

### Q1 — Validate program segment lists at start
**Severity:** medium · **Gating:** —

**Summary.** Malformed program data isn't caught at start; it throws mid-fire (the
likeliest cause of a dead runner, S3).

**Context.** `_KILN_PROGRAM_START` blindly indexes `segment_rates_c_per_hr[0]`
(`config/program-runner.cfg:44`); programs set three parallel lists by hand with no
length check (e.g., `config/programs/bisque_06.cfg:33-35`).

**Proposed fix.** Assert at start (operator present) that all three lists are
non-empty and length == `program_total`, else `action_raise_error`:

```jinja
{% if rates|length != total or targets|length != total
      or holds|length != total or total < 1 %}
    { action_raise_error("Program malformed: %d segments, lengths %d/%d/%d"
        % (total, rates|length, targets|length, holds|length)) }
{% endif %}
```

**References.** `config/program-runner.cfg:44`, `config/programs/bisque_06.cfg:33-35`
· related: S3 Fix 4.

---

### Q2 — Name safety thresholds as constants / single source of truth
**Severity:** low · **Gating:** —

**Summary.** Soft limits are magic numbers in the watchdog macro, so documented and
enforced limits can drift apart.

**Context.** `1250`, `-10`, `80` are hardcoded at `config/safety.cfg:49-54`; the same
numbers appear in prose comments and `docs/operator-reference.md:98-100`.

**Proposed fix.** Hold them as variables (e.g., on `_KILN_STATE`) and reference them
from the watchdog so there is one source of truth.

**References.** `config/safety.cfg:49-54`, `docs/operator-reference.md:98-100`.

---

### Q3 — `KILN_FAULT` should explicitly cancel the runner
**Severity:** low · **Gating:** —

**Summary.** `KILN_FAULT` relies on the runner reading `state='fault'` on its next
tick to self-terminate, rather than cancelling it directly.

**Context.** `KILN_FAULT` (`config/safety.cfg:32-40`) calls `KILN_ESTOP` and sets
state, but does not `UPDATE_DELAYED_GCODE ID=_KILN_RUNNER DURATION=0` the way
`KILN_ABORT` does (`config/program-runner.cfg:167`). It works today (the runner
no-ops on `fault` and stops rescheduling), but it's an implicit dependency.

**Proposed fix.** Cancel the runner explicitly in `KILN_FAULT`, matching
`KILN_ABORT`'s pattern.

**References.** `config/safety.cfg:32-40`, `config/program-runner.cfg:167`.

---

## Documentation

### D1 — `first-power-runbook.md` is stale: the control loop is already closed
**Severity:** high · **Gating:** ✅ before unattended firing

**Summary.** The safety bring-up runbook describes the SSR-to-heater conversion as
future work and the chamber as a passive observer — both now false — which misleads
anyone following it.

**Context.** `docs/first-power-runbook.md:8-18` ("Where we are": *"runner … does not
drive the SSR — chamber is a passive observer"*) and §1 (`:19-58`, "Convert SSR to a
Klipper heater") present as TODO what `config/outputs.cfg:25-40` has already
implemented (git: "Close control loop with heater_generic").

**Proposed fix.** Rewrite "Where we are" and §1 to reflect the live `[heater_generic
kiln]`; retain the PID-calibration steps (§3-4), which remain valid.

**References.** `docs/first-power-runbook.md:8-58`, `config/outputs.cfg:25-40`.

---

### D2 — Add `SAFETY.md` (safety model + single points of failure)
**Severity:** medium · **Gating:** —

**Summary.** The safety model is real but scattered across `config/safety.cfg`
comments and the runbook; a mains 1300 °C device warrants one consolidated document.

**Proposed fix.** Author `SAFETY.md` enumerating: the protection layers (SSR +
contactor + `verify_heater` + soft watchdog + MCU hard limits + body thermal fuse),
the known single points of failure (S1, S2, S3, A1), the fail-safe-on-restart
behavior (A2), and explicit "do not leave unattended until …" criteria tied to the
milestone above.

**References.** `config/safety.cfg`, `docs/first-power-runbook.md`.

---

### D3 — Docs & cleanup nits
**Severity:** low · **Gating:** —

Batch of small items:
- **Stale "planned":** README calls `[mcu host]` "(planned)" (`README.md:23`) though
  it is active (`config/kiln.cfg:15-16`) and used by the heater sensor.
- **No project LICENSE:** only the vendored font's OFL is present
  (`tools/fonts/JetBrainsMono.LICENSE`); add a top-level `LICENSE`.
- **Slow-cool wording:** docs say the PID "enforces the cooling rate"
  (`config/programs/glaze_6_slow_cool.cfg:20`), but with no active cooling the heater
  can only *fail to prevent* cooling — it can't force the kiln down faster than its
  natural loss rate. Soften the claim.
- **`M300` edge:** `S >= 10000` yields `F=0` → `SET_PIN CYCLE_TIME=0`
  (`config/feedback.cfg:16-21`); no current caller hits it, latent.

**References.** `README.md:23`, `config/kiln.cfg:15-16`,
`tools/fonts/JetBrainsMono.LICENSE`, `config/programs/glaze_6_slow_cool.cfg:20`,
`config/feedback.cfg:16-21`.

---

## What the review credits (unchanged-and-good)

- Fail-safe on restart/shutdown: contactor + heater both default to 0
  (`config/outputs.cfg:46-49`).
- Layered defense in depth: SSR + series contactor + `verify_heater` + soft watchdog
  + MCU hard limits + body thermal fuse.
- `kill_pin → gcode_button` soft-abort fix (`config/display.cfg:45-48`).
- Drift-free timing from absolute `estimated_print_time` deltas
  (`config/program-runner.cfg:77-78, 100`).
- Generic runner + data-driven program library — adding a schedule is a data file.
- Literate, high-quality comments throughout; the README "Gotchas" section is real
  institutional knowledge.
