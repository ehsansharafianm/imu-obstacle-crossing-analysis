---
tags: [step, sync, export]
aliases: [step3, step03_plot_imu_and_joints_data]
---

# Step 3 — Dot vs Awinda Sync + Export

**File:** `Analysis/step03_plot_imu_and_joints_data.m`
Reads both IMU systems, converts to Euler, **syncs** them, **upsamples to 60 Hz**, pulls in the
IK joint angles, and exports one combined dataset.

## What it does
1. Reads Awinda (`.txt`) and Dot (`.csv`) for every body.
2. Orientation → **Euler ZXY (deg)** (Awinda seq `ZXY`, Dot `ZYX` reordered) → stored as `[Z X Y]`.
3. Strips the Dot terrain packet offset (`mod 1e6`), crops Dot to the common packet window.
4. **Syncs** Awinda to Dot on the first left-foot lift peak (X angle), **upsamples to 60 Hz**.
5. Loads IK joint angles, applies the same time shift, resamples onto the 60 Hz grid.
6. Plots (sync check, IMU comparison, combined) and exports.

## Joint keep-filter (what carries downstream)
Keeps hip/knee/ankle **and** shoulder/elbow: `arm_flex`, `arm_add`, `elbow_flex`.
Dropped: knee `beta`, `hip_rotation`, and **`arm_rot`** (long-axis rotation — least reliable from
one IMU, dropped by analogy with hip_rotation). Add `arm_rot` back in the `keepJ` filter to keep it.

## Outputs (`Results/Parameters Output/Test N/`)
- **`AllData_TestN.xlsx`** — sheets per segment (Dot/Awinda Foot/Thigh/Shank, Pelvis+Sternum,
  **Awinda IMUs Arms**, and `Joints`).
- **`AllData_TestN.mat`** — `Data` struct: `.time`, `.fs`, `.sync`, `.imu(k)` (Euler/packet/acc/gyro/quat), `.joints`.
- Figures: sync check, IMU comparison, combined (joints + IMU).

## Partial trials — Dot drives the grid, Awinda blanks (2026-10-12)
The shared time grid used to be the **overlap** of all sensors (`min` of ends), so if the Awinda stopped
early it truncated the whole dataset. Now the grid **starts** at the common start and **ends at the full
Dot coverage**; Awinda Euler channels and the OpenSim joints past their end are **NaN (blank)** (via
`interp1` with no `extrap`). So the Dot (and everything derived from it — ZVP, ZHC, stride, clearance) is
processed to **full length**, and Awinda/joints simply stop where the link died. Prints a `NOTE:` when it
extends. Identical to before when the two systems are the same length. Motivated by the **Test 103 Awinda
mid-trial collapse** — see [[Heading Drift and De-drift]] and [[Lab Checklist - IMU Drift]].

## Serial-flexible right-side sensors
Right thigh/shank/foot each accept a **new** serial with the **old** as auto-fallback, so one config runs
old and new trials: thigh `00B4AB24`/`2B`, shank `00B4AB30`/`27`, foot `00B4AB32`/`29`. Prints `[fallback]`
when the old serial is used. Mirrored in `step1` (`altIds`) and `diag_drift_check.m`.

## ⚠️ Fixes / gotchas
- **Awinda `PacketCounter` rollover** — 16-bit counter wraps at 65536. On Test 13 it started at
  57954, wrapped through 0, breaking the packet-derived time (empty resample grid). Fixed with
  `unwrapCounter(pkt, 65536)` in the Awinda branch. See [[Session Changelog]].
- Right Thigh & Right Shank (Awinda) Euler angles are negated for sign consistency (arms are not).

## Sign check (QC)
After loading joints + IMUs, `signCheckStep3` compares **left vs right** dominant excursion direction
for hip/knee/ankle (IK) and thigh/shank/foot (Dot). Both legs do the same motion, so their sign
conventions should match; a mismatch means a limb's **sensor-to-body calibration is probably flipped**.
Each signal is **detrended** (~2 s running median) first so drift doesn't skew the result. It **only
prints warnings — it does not change the saved data**; the group step normalizes signs data-driven for
the analysis (see [[Step 9 - Group Crossing Analysis]], `signNormTools`). In this cohort it consistently
flags the **right ankle** as opposite the left on every participant (a systematic calibration quirk worth
knowing), plus per-participant hip/knee flips. There is **no angle wrapping** — these are pure sign flips.

Next: [[Step 4 - Segmentation (ZVP)]] · back to [[Pipeline Workflow]] · see [[Data and Sensors]]
