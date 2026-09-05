---
tags: [step, camera, leading-trailing, features]
aliases: [step8, step8_segment_features_with_camera]
---

# Step 8 — Leading/Trailing Features (with Camera)

**File:** `Analysis/step8_segment_features_with_camera.m`
Everything [[Step 5 - Obstacle Features]] does (read the FeatureLogs + Logger, classify each obstacle
cycle **Leading/Trailing** per terrain, plot every IMU / joint / ZHC signal by side and by role) —
**plus** the camera foot-marker heights, in the same group viewers.

## Inputs
- `Data/Dot IMUs/Test N/` — `FeatureLog_IMU1/2_*.csv` + `Logger*.txt` (leading-leg lines).
- `AllData_TestN.mat` ([[Step 3 - Dot vs Awinda Sync]]), `SegmentedParams_TestN.mat`
  ([[Step 4 - Segmentation (ZVP)]]), `CameraSynced_TestN.mat` ([[Step 6 - Camera Sync and Viewers]]).

## What it does
- Reuses step 5's machinery (window→stride matching, leading/trailing labelling, interactive
  Unknown resolution) and **adds** camera L/R toe & heel height (Z) segmented on the same ZVP cycles.
- Shows Camera **Left-vs-Right** and **Leading-vs-Trailing** viewers (gait % and time), reusing
  step 5's grouped-stride viewer.

## Outputs (`Results/Parameters Output/Test N/`)
- **`SegTrajectories_WithCamera_TestN.mat`** (`S5` incl. `S5.camera.*`: per-cycle camera heights
  tagged side/terrain/role). A **different** filename so it doesn't clobber step 5's
  `SegTrajectories_SideBased`.

> [!important] This is what step 9 slices
> `S5.camera.terrainL/roleL/terrainR/roleR` (per-cycle labels) are how [[Step 9 - Crossing Parameters]]
> knows which cycles are crossings and each leg's role.

test22: the camera reproduces the classic pattern — leading toe clears higher/earlier than trailing.

Prev: [[Step 7 - Camera Stride Segmentation]] · next: [[Step 9 - Crossing Parameters]]
