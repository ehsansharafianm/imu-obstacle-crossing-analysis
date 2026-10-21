---
tags: [step, group, cohort, crossing, results]
aliases: [step9, group analysis, group_crossing_analysis]
---

# Step 9 — Group Crossing Analysis

**File:** `Analysis/step9_group_crossing_analysis.m`
The pipeline **capstone**: run ONCE after steps 1–8 are complete for every participant. It reads
**many tests** (not one) and aggregates them into **group** results (mean ± SD **across participants**).
Set `TESTS` to the cohort; Subject ID = Test number.

## Two-level average
Per participant, mean per condition first; then mean ± SD **over participants** — so everyone weighs
equally regardless of how many crossings they did. **No normalization** (absolute cm / deg / % GC).
Conditions = terrain `W{1,2}_H{1,2,3}` × role **Leading/Trailing**; `Level_Walk` = baseline.

## Metrics
- **Tier 1 (camera, cm):** toe clearance, heel clearance, **min clearance**, take-off (lift) distance,
  landing distance. *Min clearance* = lowest foot height over the obstacle footprint − top (includes the
  y=0 interpolated value so **min ≤ toe** always); can go negative = contact.
- **Spatiotemporal (crossing stride):** **stride length (cm)**, **cadence (steps/min = 120/stride-time)**,
  **speed (m/s)** — from ZHC net-XY + ZVP→ZVP stride time.
- **ROM (deg):** joint (hip/knee/ankle) and **IMU segment** (foot/shank/thigh, Dot) = max−min per stride,
  pooled by limb role.
- **Peak timing (% gait cycle):** when the reported extremum occurs in the ZVP→ZVP cycle. The extremum is
  **per-signal** (`PK_EXTREMUM`): hip=min, knee=min, ankle=max, foot height=max, foot=min, shank=min,
  thigh=max. Drift-robust (timing survives offsets).

## Test 106 cleaning (group-only; steps 1–8 untouched)
A mid-trial thigh-IMU artifact inflated 106's hip/knee/thigh ROM & peak timing. The `CLEAN` config applies
**only to 106 and only those signals**: (a) MAD-gate + median, (b) drop obstacle codes 11/13/23
(`W1_H1`/`W1_H3`/`W2_H3`). See [[Heading Drift and De-drift]].

## Outputs (`Results/Group Analysis/`)
- `GroupCrossing_<cohort>_Results.md` — **human/LLM-readable** tables (mean ± SD per condition).
- `GroupCrossing_<cohort>_Summary.xlsx` — sheets: Tier1_cm, Spatiotemporal, ROM_deg, SegmentROM_deg, PeakTiming_pctGC.
- `GroupCrossing_<cohort>.mat` — the aggregated `G` struct (+ `G.perParticipant`) for re-plotting/stats.
- `Figures/` — Tier1, **Peak angles + ROM (HipThigh / KneeShank / AnkleFoot)**, Spatiotemporal,
  PeakTiming (Joints/FootHeight/Segments). **PNG only.** (ROM now lives inside the combo peak
  figures, so the standalone JointROM/SegmentROM figures were removed; ROM tables stay in md/xlsx.)

## Named peak angles (figures)
Peaks are **whole-cycle extrema referenced to the begin-ZVP (stance) posture** (`PEAKDEF` sets the signal
+ extremum + P/S role). Bars = the peak **value** (`Peak angle (deg)`), red dashed line = the **level-walk**
value, so the gap to the red line *is* the change vs level walk (`% vs level` labels say it numerically).
Three figures, each a **joint ROW then its IMU-segment ROW**, with the directional peak(s) **plus that
structure's ROM** on each row (via `drawComboFigure`), drawn **before** the ROM-only figures:
- **Hip & thigh** (2×3): hip flexion / extension / ROM; thigh flexion (fwd tilt) / extension (back tilt) / ROM.
- **Knee & shank** (2×3, top row 2): knee flexion / knee ROM; shank backward / forward / ROM.
- **Ankle & foot** (2×3): ankle plantarflexion / dorsiflexion / ROM; foot toe-down / toe-up / ROM.
Paired **Δ vs level walk** stays in the `.md`/`.xlsx` tables (`PeakExcursion_deg`, `PeakDelta_deg`).

## Sign handling + which peaks are valid ([[Heading Drift and De-drift]])
The IK joint angles (and occasionally the Dot tilts) come out with **inconsistent signs between the two
legs and between trials/participants** (a rotated sensor-to-body calibration flips a limb's angle), which
corrupts any *directional* flexion/extension peak. There is **no angle wrapping** (max per-sample jump ≤12°),
so the fix is a sign flip. Two mechanisms, by signal:
- **Sign-normalized** (`Analysis/signNormTools.m`): **hip, ankle, thigh, shank, foot**. For each, a level-walk
  **reference template** is built once (iterative correlation alignment + physiological polarity anchor) and
  saved to `signTemplates.mat`; each participant×side whose level-walk curve correlates negatively with it is
  flipped before peaks/timing. Lets `ext='min'/'max'` mean dorsi/plantar, fwd/back, etc. consistently.
- **Sign-invariant** (`ext='abs'`): **knee flexion** = `max(|y − stance|)`. The knee only flexes (extension
  past neutral is negligible), so the single dominant excursion = flexion, no sign needed; ≈ knee ROM.
- **ROM** (max−min) is sign-invariant either way, so it and all `OVERRIDE`s are untouched.

**Reliability:** hip/thigh/shank/foot + knee flexion + **ankle dorsiflexion** read physiological. **Ankle
plantarflexion** (and ankle ROM) are directionally correct but **drift-inflated** on ~half the participants
(60–160°) — treat as low-confidence; clean / `OVERRIDE` as for the other noisy joints.

## % change vs level walk + manual overrides
- Each bar on the ROM / spatiotemporal / peak-timing figures shows the **% change vs level
  walk** above it (toggleable via a `% vs level` checkbox), and the `.md` cells carry `(+X%)`.
  Not on Tier-1 (level walk isn't a meaningful baseline there).
- **Manual overrides** (`OVERRIDE` table, one row = `{GROUP, SIGNAL, CONDITION, MEAN, SD}`): replace
  any computed group mean/SD by hand (NaN = keep computed), in shown units; feeds figures + md + xlsx.
- **Markdown results** (`GroupCrossing_<cohort>_Results.md`) = all tables as `mean ± SD (% vs level)`.

## Style + interaction
All figures share the `ST` style block (Arial bold, thick box, grid off, template palette, sharp-red
level-walk line) and a left **checkbox panel** to show/hide Leading / Trailing / Level-walk; the exported
PNG renders only the chart (no checkboxes).

## Definition figures (presentation helper)
**File:** `Analysis/definition_figures.m` — illustrates what each parameter MEANS from one example
participant (grid off, PNG → `Figures/Definitions/`):
- `def_Crossing` — toe & heel sagittal trajectory over the obstacle with take-off / landing / toe clearance.
- `def_ROM` — example stride (joint + segment) with max, min, ROM = max−min.
- `def_PeakAngles` — 2×2 (hip / thigh / shank / foot), Leading (blue) vs Trailing (orange) with each named
  peak marked as an excursion from stance. Only the **sign-stable** directional signals (knee/ankle joints
  omitted — defined by ROM); sign-normalized via `signNormTools` so both legs read the same direction.

Prev: [[Step 8 - Crossing Parameters]] · back to [[Home]]
