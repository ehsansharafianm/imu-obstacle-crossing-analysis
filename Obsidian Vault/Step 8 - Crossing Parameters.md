---
tags: [step, camera, clearance, parameters, obstacle]
aliases: [step8, step8_crossing_parameters]
---

# Step 8 — Crossing Parameters (Placement & Clearance)

**File:** `Analysis/step8_crossing_parameters.m`
The payoff step: per obstacle-crossing cycle, read the **camera** foot positions at the key **IMU**
moments and report the crossing parameters. Obstacle heights default to **AUTO** (measured from the camera
obstacle markers); leg length or explicit heights can be entered instead (see Obstacle heights below).

## Inputs
- `CameraSynced_TestN.mat` ([[Step 5 - Camera Sync and Viewers]]) — positions.
- `SegmentedParams_TestN.mat` ([[Step 4 - Segmentation (ZVP)]]) — ZVP indices.
- `SegTrajectories_WithCamera_TestN.mat` ([[Step 7 - Leading-Trailing Features (Camera)]]) — which
  cycles are crossings + Leading/Trailing role.

## Obstacle model
Centred at **y = 0**, base on floor. Widths fixed: W1 = 50 mm, W2 = 150 mm → near edge = −w/2, top = height.

## Obstacle heights — three ways (default AUTO, 2026-10-12)
Prompt: `[Enter]=AUTO (from obstacle markers)  or  <legLen_cm>  or  [h1 h2 h3]`.
- **AUTO (default)** — from the camera **obstacle markers**. The two markers (`obstacle1`/`obstacle2`) are the
  **two ends of one bar** (same y≈0 crossing line, opposite x ends ±~370 mm, same height ±~6 mm), so their Z is
  **averaged per frame** (combines both + fills dropouts). Per crossing: obstacle top = **MAD-gated median** of
  that signal over the ZVP cycle (rejects occlusion spikes). Crossings are **grouped by H-level** (read from the
  terrain label) and each level = **median across its crossings** — robust even when two levels are close
  (grouping is by the known label, not by value). **Applied = measured − `MARKER_RADIUS_MM` (25 mm = 2.5 cm)** to
  get the plate top (markers sit at the sphere centre). Prints `measured → applied` + per-level n and ~SD; press
  Enter to accept or type an override. Falls back to manual if an H-level has no marker data.
- **One number** = leg length cm → H1/H2/H3 = 10/20/30 % (not radius-corrected; it's already the plate height).
- **`[h1 h2 h3]`** = the three heights in cm, used directly (not radius-corrected).
- Saved provenance: `CP.heightSource` (`auto-markers`/`manual`), `CP.markerRadius_mm`.
> [!note] AUTO averaging assumes **one bar per block** (both markers at the same height). If two different-height
> bars are ever used simultaneously, switch to nearest-marker-per-crossing instead.

## Parameters (per crossing, toe & heel)
- **Placement:** y at **begin-ZVP** (before the obstacle) and at **land-ZVP** (after).
- **Lift distance** = toe (begin-ZVP) → near edge; **landing distance** = heel (land-ZVP) → near edge.
- **Height clearance at y = 0** = `z@y=0 − obstacle top`.
- **Minimum clearance across the depth** = lowest foot z while `y ∈ [−w/2, +w/2]` − top
  (the meaningful clearance; **can be negative = contact**).

Positions come from the camera; the moments (ZVP) come from the IMU ([[Step 4 - Segmentation (ZVP)]]).

## Figures
- **Interactive crossing-arc viewer** (z vs y): toggle Terrain, Leading/Trailing, Toe/Heel, moment
  markers, and the **symbolic obstacle** (drawn to scale, shows/hides with its terrain). Leading =
  solid, trailing = dashed; toe thick, heel thin. Legend keys: o begin-ZVP, □ land-ZVP, ◇ z@y=0, ★ min.
- **Parameter bars** (Terrain × Leading/Trailing): the six raw params.
- **Clearance bars** (2×2): lift distance, landing distance, height clearance @ centre, MIN clearance.

## Outputs (`Results/Parameters Output/Test N/`)
- **`CrossingParams_TestN.mat`** (`CP`) + **`.xlsx`** — one row per crossing with all parameters.
- PNGs: `CrossingArcs`, `CrossingParamsBars`, `CrossingClearanceBars`.

test22 (leg 90 cm): leading planted ~950 mm back & clears highest; trailing lands ~600–800 mm past &
clears lowest; min clearance falls with obstacle height (tallest/widest → a slightly negative heel min).

Prev: [[Step 7 - Leading-Trailing Features (Camera)]] · related: [[Camera Pipeline - Achievements]]
