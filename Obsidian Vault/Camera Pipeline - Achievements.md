---
tags: [achievement, camera, summary, milestone]
aliases: [Achievements, Camera Integration, Progress 2026-09]
---

# 🎉 Camera Pipeline — Achievements & Progress

The **third measurement stream is fully integrated.** The WorldViz/CV camera markers are now
synced to the IMU/OpenSim clock, cleaned, segmented, and turned into obstacle-crossing parameters —
end to end, per limb, per obstacle. What was "in progress" in [[Camera Sync Strategy]] is done.

## The headline
From three independent systems (Awinda 40 Hz, Dot 60 Hz, camera ~60 Hz) we now produce, for **every
obstacle crossing**, the classic biomechanics numbers **from the camera**, timed by the **IMU** gait
events, and grouped by **leading vs trailing** limb and by **obstacle** (height × depth):

- **Foot placement** before/after the obstacle (lift & landing distances).
- **Height clearance** over the obstacle — at the centre *and* the **minimum across the depth**
  (which can go negative = a foot dipping below the top).
- Full **z-vs-y crossing arcs** with the obstacle drawn to scale.

The results are physiological on the very first full test (test22): the **leading limb** is planted
farther back and clears **higher**; the **trailing limb** lands farther and clears **lower**; and the
minimum clearance shrinks as obstacles get taller. That agreement across systems is the validation.

## The chain we built
1. **Refine (CV side)** — `matlab/refine_trajectory.m` in the CV repo cleans the raw reconstructed
   marker workbook → `testN_trajectory_refined.xlsx` (despike out-of-volume / non-negative height,
   short-gap fill, smoothing) and drops it straight into `Data/Camera CV/Test N/`. See [[Camera Tracking (WorldViz PPT)]].
2. **[[Step 6 - Camera Sync and Viewers]]** — sync the camera to the 60 Hz IMU grid via the 3× left-leg
   raise gesture (one shift; ~0 drift over the trial), then explore everything together (angles,
   trajectories vs time, 3D) with gait-event overlays.
3. **[[Step 7 - Camera Stride Segmentation]]** — cut the camera foot markers into strides on the
   **same ZVP boundaries** as the IMU, and overlay the ZHC IMU foot height for a direct comparison.
4. **[[Step 8 - Leading-Trailing Features (Camera)]]** — add the camera to step 5's leading/trailing
   feature analysis, per terrain.
5. **[[Step 9 - Crossing Parameters]]** — the payoff: placement + clearance parameters and figures.

## Why it works
- **One clock.** Everything lands on `Data.time` (60 Hz). The camera's clap-synced timestamps plus the
  shared left-leg-raise gesture align it to the IMU to within ~0.01 s over 150 s. See [[Camera Sync Strategy]].
- **IMU defines *when*, camera measures *where/how high*.** ZVP/toe-off/heel-strike come from the foot
  IMU roll angle ([[Step 4 - Segmentation (ZVP)]]); the camera supplies the 3D position at those moments.
- **Honest about coverage.** The camera only sees the foot in ~35 % of frames (the rest is out of
  volume between passes); gaps stay NaN rather than being invented.

## Obstacle model (test22 convention)
Obstacle **centred at y = 0**, base on the floor (z = 0). Heights = **10/20/30 %** of leg length
(`Height1/2/3`), depths = **5 cm / 15 cm** (`Depth1/2`) → the six objects. Leg length is entered at
run time (step 9).

## Status
- Steps 6–9 written, run, and committed to the analysis repo; the CV refine tool committed to the CV repo.
- Validated on **test22** (leg-length example 90 cm): 6 left + 6 right crossings, all 6 terrains
  labelled leading/trailing.
- Bar-plot error bars are zero for now (one crossing per condition) — they populate with repeated trials.

## Next
- True clearance uses the entered obstacle heights (done); refine per-test leg lengths as measured.
- More participants/trials to fill the Terrain × Leading/Trailing statistics.

Related: [[Pipeline Workflow]] · [[Outputs and File Formats]] · [[Session Changelog]] · [[Home]]
