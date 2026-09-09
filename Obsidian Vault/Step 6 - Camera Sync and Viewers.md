---
tags: [step, camera, sync, viewer]
aliases: [step6, step6_camera_sync_and_view]
---

# Step 6 — Camera Sync + Viewers

**File:** `Analysis/step6_camera_sync_and_view.m`
Syncs the camera marker trajectory to the IMU/joint 60 Hz grid, then opens three interactive
viewers. (Combines the earlier sync step and the "view all synced signals" step.)

## Inputs
- `Data/Camera CV/Test N/` — the reconstructed marker workbook; **prefers `*_refined.xlsx`**
  (from the CV-side `refine_trajectory`), else `*_trajectory.xlsx`. Markers: L/R toe & heel +
  obstacle1/2, x/y/z in **mm**, **z = height**, `time_s = 0` at the clap.
- `AllData_TestN.mat` (from [[Step 3 - Dot vs Awinda Sync]]) — the 60 Hz IMU/joint grid.
- `SegmentedParams_TestN.mat` (from [[Step 4 - Segmentation (ZVP)]]) — optional, adds ZHC/ZVP overlays.

## What it does
- **Sync gesture:** the subject raises the left leg 3× at the start and 3× at the end. Find the first
  raise peak in the camera `L_toe` height and in the IMU `Left Foot (Dot)` Euler-X, and shift the
  camera clock so they coincide (single shift; the end triplet gives a drift check — ~0 for test22).
  Both are ~60 Hz, so it's an interp onto `Data.time`, **not** a rate change; `time_s` untouched;
  real dropouts stay NaN. See [[Camera Sync Strategy]].
- **Auto or manual (prompt):** at startup it asks `Sync automatically? (y/n) [Enter = auto]`.
  - **Auto** (default): the peak-based sync above (unchanged).
  - **Manual** (`n`): pops a **preview** of both signals (amplitude-normalised, unshifted), prints the
    auto-detected peaks, then asks for the **IMU peak time** and the **camera peak time** (press Enter
    to accept the auto value). It computes `offset = IMU peak − camera peak` itself and reports the
    end-triplet residual as a self-check (small = well aligned). Use manual when auto locks onto a
    wrong peak (e.g. a walking swing instead of the raise gesture). `offset` convention: applied as
    `tCam + offset`, so **positive shifts the camera later**.
- **Viewers (all on the shared clock):**
  1. **Angles vs time** — every IMU Euler + OpenSim joint angle (listbox).
  2. **Trajectories vs time** — camera markers + ZHC IMU foot height; per-leg gait-event overlays
     (ZVP o, toe-off v, heel-strike square) each with its own toggle, an optional **foot-angle**
     right-axis sanity overlay, an obstacle toggle, and auto-fit.
  3. **Trajectories 3D** — X/Y/Z paths, rotatable.

## Outputs (`Results/Parameters Output/Test N/`)
- **`CameraSynced_TestN.mat`** (`Cam`) + **`.xlsx`** — camera markers on the 60 Hz grid + sync summary.
- **`CameraSync_TestN.png`** — the sync-check figure.

> [!note] Batch
> Set `TN` before running to skip the prompt. Only step 6 reads `Data/Camera CV/`; steps 7–9 read the
> `CameraSynced` file, so refining + re-running step 6 propagates everywhere.

Next: [[Step 7 - Camera Stride Segmentation]] · related: [[Camera Pipeline - Achievements]] · [[Outputs and File Formats]]
