---
tags: [step, camera, clearance, parameters, obstacle]
aliases: [step8, step8_crossing_parameters]
---

# Step 8 — Crossing Parameters (Placement & Clearance)

**File:** `Analysis/step8_crossing_parameters.m`
The payoff step: per obstacle-crossing cycle, read the **camera** foot positions at the key **IMU**
moments and report the crossing parameters. Prompts for **leg length (cm)**.

## Inputs
- `CameraSynced_TestN.mat` ([[Step 5 - Camera Sync and Viewers]]) — positions.
- `SegmentedParams_TestN.mat` ([[Step 4 - Segmentation (ZVP)]]) — ZVP indices.
- `SegTrajectories_WithCamera_TestN.mat` ([[Step 7 - Leading-Trailing Features (Camera)]]) — which
  cycles are crossings + Leading/Trailing role.

## Obstacle model
Centred at **y = 0**, base on floor. Height = 10/20/30 % of leg length (`Height1/2/3`), depth =
5/15 cm (`Depth1/2`) → near edge = −w/2, top = height. Leg length entered at run time.

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
