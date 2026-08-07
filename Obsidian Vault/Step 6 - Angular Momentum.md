---
tags: [step, angular-momentum, balance, opensim]
aliases: [step6, step6_angular_momentum, WBAM]
---

# Step 6 — Angular Momentum

**File:** `Analysis/step6_angular_momentum.m`
Whole-body **and** segmental angular momentum about the body centre of mass (COM), in the model
Ground frame. Standalone add-on — reads only step-1 outputs, **does not modify steps 1–5**.

## Why it's possible with IMU data
Angular momentum is purely **kinematic + inertial** — it needs the model's segment masses/inertias
and the motion, but **no ground-reaction or muscle forces**. WBAM about the COM is also
**translation-invariant**, so it's valid even though IMU IK has no global translation.

## Method
1. Load calibrated `.osim` + newest `ik_*.mot` ([[Step 1 - OpenSense IK]]).
2. Low-pass the IK coordinates (`LOWPASS_HZ = 6`), central-difference for **generalized speeds**
   (IK gives positions only — this is the one essential extra step).
3. Per body: `H_i = R·I_i·Rᵀ·ω_i + m_i (r_i−r_com)×(v_i−v_com)` (spin + orbital).
4. Whole-body = **sum of segments**, cross-checked against Simbody's `calcSystemCentralMomentum`
   (prints max diff — should be ~0).
5. Group into **Arms / Legs / Trunk**. Normalize: `H / (m·V·L)` (dimensionless, mass-scale invariant).

## Body features (two options)
Set at the top: `ASK_BODY_FEATURES = false` uses hard-coded `BODY.*` defaults (mass, height, leg
length, speed); `= true` prompts for each. Mass only rescales absolute momentum; leg length and
speed (given, or derived from the [[Step 5 - Obstacle Features]] ZHC path) set the normalization.

## API note
Uses version-robust calls: inertia via `Body.get_inertia()` (`Vec6`), rotation via
`expressVectorInGround` (avoids `toMat33`/`Rotation.get`, which aren't wrapped in all bindings).

## Figures & outputs
- **Interactive viewer** — checkbox toggle per entity (Whole body / Arms / Legs / Trunk / each
  segment), axis checkboxes (X/Y/Z/|H|), raw↔normalized switch, Save PNG. (The old static overview
  figure was removed.)
- **`AngularMomentum_TestN.mat`** — `AM` struct: whole-body `.H_model/.H_subject/.H_norm/.Hmag`,
  `.seg` per-segment, `.group` Arms/Legs/Trunk. **`.xlsx`** = whole-body + group components.
- Prints total processing time (`tic/toc`).

## Not yet
Per-stride / terrain / leading-trailing tagging (needs aligning the IK time base to the step-3
synced grid) — planned follow-up.

Related: [[Step 5 - Obstacle Features]] · [[Session Changelog]] · back to [[Pipeline Workflow]]
