---
tags: [lab, checklist, imu, drift, hardware, mt-manager]
aliases: [imu checklist, drift checklist, lab checklist]
---

# Lab Checklist — IMU Heading Drift

One page to diagnose and reduce the Awinda heading drift. Context in
[[Heading Drift and De-drift]]. Worst offenders so far: **pelvis `00B4AB22`**,
**right thigh `00B4AB2B`**, right side / sharp turns.

> **Key idea:** the drift *moves* (different sensor bad on different trials) → it is
> mostly **environmental (magnetometer)**, not a broken sensor. Do the bench test
> first; it tells you which problem you actually have.

## 0. Decisive bench test — sensor vs environment  ⭐ do this first
- [ ] Strap `00B4AB2B`, `00B4AB22`, **+ one known-good sensor** to a **rigid non-magnetic board** (wood/plastic, no screws).
- [ ] In MT Manager, record ~2 min in an **open area away from all metal**: 30 s still → slow rotations through all headings → 30 s still.
- [ ] Since they're rigidly linked, their **relative heading must stay constant**. Watch yaw of all three.
- **Result:**
  - [ ] All three **agree** in open space → sensors are fine, it's the **room** → go to §2 (environment).
  - [ ] A suspect **drifts** in open space → that unit is **faulty (magnetized)** → §1 MFM / RMA.

## 1. MT Manager — sensor checks
- [ ] **Magnetic Field Mapping (MFM)** on each sensor, **mounted as used**. (Main sensor-side fix; recovers a magnetized unit.)
- [ ] **Magnetometer self-test / status** per sensor — flag any with an abnormal field norm.
- [ ] **Firmware** current and **identical** on all sensors (record the version).
- [ ] **Batteries** hold charge + solid RF link for a full ~4-min trial (brown-outs look like drift).
- [ ] Note which sensor ID is on which body segment (mounting map) — rule out a swap.

## 2. Environment / setup  (likely the bigger win)
- [ ] **Magnetic survey the walking loop:** walk one sensor slowly around it, watch the mag reading; find the source (force-plate wiring, rebar/metal in floor, the obstacle frame, a cart). The **sharp-turn side** is the prime suspect.
- [ ] **Move sensors a few cm off any metal** (marker-cluster plates, brace hinges, buckles).
- [ ] **Reconsider the path:** if the sharp turn passes a metal source, use a **straighter / wider** turn so the worst rotation isn't next to the disturbance.

## 3. Capture settings
- [ ] Try **filter profile → VRU** (magnetometer-independent) + **Initial Gyro Bias Update** on. Note: on MTw2 fw 4.6.0 the **VRU setting does not persist** (reverts to `human`) — confirm whether it holds this session.
- [ ] Start every recording with a **few seconds of stillness** (gyro-bias settle + calibration + sync).
- [ ] **Movella support:** report "MTw2 fw 4.6.0 will not persist the VRU/XDA filter profile" (likely a firmware bug) and ask about **AHS** availability for MTw2.

## 4. Verify a capture is clean (before trusting a trial)
Run a **3-min pilot** (walk the loop with the turns), then in `step1` read the
**orientation tracking-error summary**:
- [ ] Every lower-limb IMU **< ~10° mean** (healthy trials 13/14 are ~8°; the bad Sept trials were 40–80°).
- [ ] Or run `diag_drift_check.m` — the `drift(deg)` column single-digit, midline flat.
- [ ] `pelvis`/`torso` near 0° (they're the heading-lock reference — a drifting pelvis poisons everything, cf. Test 102).

## Resolution (2026-09-14) — bench test done: sensors are clean, it was capture quality
The §0 bench test and a designed turn/sensor experiment were run (full write-up in
[[Heading Drift and De-drift]]). Outcome:
- **Bench (rigid board):** suspect `00B4AB2B` agreed with two other sensors within **3.6–7°** → **clean**.
  No unit is reliably bad; a **~5–25° environmental heading-drift floor** exists on the bench.
- **Decisive:** the **pelvis** (`00B4AB22`, never swapped) went **23.6° → 0.1°** between two sharp-right-turn
  trials at the **same spot** — so only the **recording session** changed, not the hardware.
- **The lever that fixed it:** **stand still ~5–10 s at the start of every recording** (gyro-bias + heading
  init), plus gentle turns. Tests 28/29/30 with this recipe hold pelvis/torso ≈ 0° through sharp turns.
- **MFM** was attempted but not needed (units are healthy); right-leg sensors were swapped to a new set for
  convenience (`2B→24`, `27→30`) with the pipeline made serial-flexible (old serials auto-fallback).
- **Quick check tool:** `diag_drift_check.m` (per-sensor drift + IK error across trials).

## Bottom line
The **bench test (§0)** is the decider — and it cleared the sensors. The real fixes are the
**capture protocol (still-start, §3) + gentler turns (§2)**, not the hardware. Add the
**still-start** to every recording and verify with `diag_drift_check.m` (pelvis/torso ≈ 0°, legs < ~10°).

Related: [[Heading Drift and De-drift]] · [[Data and Sensors]] · [[Home]]
