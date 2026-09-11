---
tags: [step, camera, leading-trailing, features]
aliases: [step7, step7_segment_features_with_camera]
---

# Step 7 — Leading/Trailing Features (with Camera)

**File:** `Analysis/step7_segment_features_with_camera.m`
Everything [[Step 5 - Obstacle Features]] does (read the FeatureLogs + Logger, classify each obstacle
cycle **Leading/Trailing** per terrain, plot every IMU / joint / ZHC signal by side and by role) —
**plus** the camera foot-marker heights, in the same group viewers.

## Features: all-IMU (ZHC) + camera validation, and max/min bars  (2026-09-11)
- **Height + stride from ZHC** (one source): height = peak Z, stride = net-XY displacement per ZVP
  cycle, for every stride (crossing + level walk). The Movella-Dot-app `Max_Height/Max_Stride` are
  **retired** (the app is used only to mark which strides are Level_Walk).
- **Camera validation:** the camera foot-marker peak-Z is kept as `heightCam` (console summary +
  `Left/Right_HeightCam_m` in the export) for IMU-vs-camera agreement.
- **Max/min bar figures:** per terrain (Level_Walk + every W/H) x Leading/Trailing — one figure for
  IMUs (Thigh/Shank/Foot, **Dot** reference) and one for joints (hip/knee/ankle), each MAX | MIN.
  Level_Walk (no role) is the baseline in both bars. Knobs: `BARMM_IMU_SYSTEM`, `BARMM_IMU_SEGS`,
  `BARMM_JOINTS`.
- **Reporting note:** absolute angles are drift-limited — prefer **ROM (max−min)**, camera clearance,
  and stride length as the clean metrics. See [[Heading Drift and De-drift]].

## Inputs
- `Data/Dot IMUs/Test N/` — `FeatureLog_IMU1/2_*.csv` + `Logger*.txt` (leading-leg lines).
- `AllData_TestN.mat` ([[Step 3 - Dot vs Awinda Sync]]), `SegmentedParams_TestN.mat`
  ([[Step 4 - Segmentation (ZVP)]]), `CameraSynced_TestN.mat` ([[Step 5 - Camera Sync and Viewers]]).

## What it does
- Reuses step 5's machinery (window→stride matching, leading/trailing labelling, interactive
  Unknown resolution) and **adds** camera L/R toe & heel height (Z) segmented on the same ZVP cycles.
- Shows Camera **Left-vs-Right** and **Leading-vs-Trailing** viewers (gait % and time), reusing
  step 5's grouped-stride viewer.

## Outputs (`Results/Parameters Output/Test N/`)
- **`SegTrajectories_WithCamera_TestN.mat`** (`S5` incl. `S5.camera.*`: per-cycle camera heights
  tagged side/terrain/role). A **different** filename so it doesn't clobber step 5's
  `SegTrajectories_SideBased`.

> [!important] This is what step 8 slices
> `S5.camera.terrainL/roleL/terrainR/roleR` (per-cycle labels) are how [[Step 8 - Crossing Parameters]]
> knows which cycles are crossings and each leg's role.

test22: the camera reproduces the classic pattern — leading toe clears higher/earlier than trailing.

Prev: [[Step 6 - Camera Stride Segmentation]] · next: [[Step 8 - Crossing Parameters]]
