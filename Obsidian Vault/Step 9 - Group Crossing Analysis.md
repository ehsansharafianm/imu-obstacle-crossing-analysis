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
- `Figures/` — Tier1, Spatiotemporal, JointROM, SegmentROM, PeakTiming (Joints/FootHeight/Segments). **PNG only.**

## Style + interaction
All figures share the `ST` style block (Arial bold, thick box, grid off, template palette, sharp-red
level-walk line) and a left **checkbox panel** to show/hide Leading / Trailing / Level-walk; the exported
PNG renders only the chart (no checkboxes).

## Definition figures (presentation helper)
**File:** `Analysis/definition_figures.m` — illustrates what each parameter MEANS from one example
participant (grid off, PNG → `Figures/Definitions/`):
- `def_Crossing` — toe & heel sagittal trajectory over the obstacle with take-off / landing / toe clearance.
- `def_ROM` — example stride (joint + segment) with max, min, ROM = max−min.
- `def_PeakTiming` — 3 rows (joints / segments / foot-height-middle); only the **reported** extremum (red).

Prev: [[Step 8 - Crossing Parameters]] · back to [[Home]]
