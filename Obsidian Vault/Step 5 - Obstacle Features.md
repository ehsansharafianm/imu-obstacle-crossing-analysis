---
tags: [step, obstacle, leading-trailing, clearance]
aliases: [step5, step5_plot_segmented_features]
---

# Step 5 — Obstacle Features (Side & Leading/Trailing)

**File:** `Analysis/step5_plot_segmented_features.m`
Links the Dot **FeatureLog** windows to the step-4 strides, reads the **Logger** to label the
leading leg of each crossing, and produces the side-based and leading/trailing analyses.

## Inputs
- `Data/Dot IMUs/Test N/` — `FeatureLog_IMU1/2_*.csv` (labelled crossing windows) and
  `Logger*.txt` (leading-leg lines like `>>> Leading leg is Right for H2_D1 crossing (Start pkt: …, End pkt: …)`).
- `AllData_TestN.mat` + `SegmentedParams_TestN.mat` from [[Step 3 - Dot vs Awinda Sync]] / [[Step 4 - Segmentation (ZVP)]].

## What it does
- Keeps labelled windows, dedups contiguous same-terrain windows.
- **Matches** each window to its step-4 stride by Dot packet overlap.
- Tags each obstacle stride **Leading / Trailing / Unknown** from the Logger; asks the operator to
  resolve any Unknown crossings interactively, then re-plots.
- Builds Left/Right and Leading/Trailing stride viewers (gait % and time), plus **ZHC foot-height**
  trajectory viewers (gait %, time, and vs horizontal distance).

> [!important] Arm signals use the contralateral foot's labels
> Because arms segment on the opposite foot ([[Step 4 - Segmentation (ZVP)]]), each arm cycle's
> `terrain`/`role` come from that opposite foot, while `.side` still names the physical arm.
> Verified: no duplication, column counts match labels. See [[Session Changelog]].

## Outputs (`Results/Parameters Output/Test N/`)
- **`WindowFeatures_SideBased_TestN.xlsx`** — sheets `Left and Right`, `Leading vs Trailing`,
  `Level Walk` (stride length, max height, packets, cycle, role per crossing).
- **`SegTrajectories_SideBased_TestN.mat`** — `S5` struct: per-signal `.Y` (normalized) / `.Yt`
  (time) trajectories tagged `side` / `terrain` / `role` / `cycle`, plus `S5.zhc` foot-height
  trajectories and the `S5.zhc.all` per-cycle table (the step-6-style stats input).

## The headline result
The **foot-clearance (height) trajectory** answers the core question — how high the foot is lifted
through each crossing — per limb and terrain. Its peak is the clearance measure; shape vs gait%/time
shows *when*, vs distance shows *where* over the ground.

Prev: [[Step 4 - Segmentation (ZVP)]] · related: [[Step X - Angular Momentum]] · [[Outputs and File Formats]]
