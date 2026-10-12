---
tags: [step, segmentation, gait-events]
aliases: [step4, step4_segmentation]
---

# Step 4 — Segmentation (ZVP)

**File:** `Analysis/step4_segmentation.m`
Detects gait events per side, cuts every signal into strides, and reconstructs the foot path.

## ZVP baseline detrend (optional, default ON)
Prompt: `Apply ZVP baseline detrend to joints? (y/n) [Enter = y]`. For each joint it samples the value
at its **mid-stance (ZVP)**, fits a slow trend through those baselines, and subtracts it — holding the
baseline at the early-strides level (start-region median). Removes slow baseline **drift** while
keeping within-stride shape and crossing peaks (mid-stance posture is obstacle-independent).
Non-destructive (raw kept as `Data.joints.angles_deg_raw`); re-saves `AllData` so step5-8 inherit.
Knobs: `DETREND_JOINTS`, `REF_MODE` ('start'|'overall'), `REF_STRIDES`, `SMOOTH_STRIDES`, `ZVP_WIN`.
**Limit:** fixes a baseline shift, not posture-dependent residual — see [[Heading Drift and De-drift]].

## Gait events (ZVP = zero-velocity point / mid-stance)
Per side, from that side's **Dot foot IMU**:
- **Toe-offs** = inverted minima of foot **roll = Euler X**.
- **Candidates** = `|gyro| < OMEGA_THRESH` AND `|acc| < ACC_THRESH` (flat foot).
- One **ZVP** = midpoint of candidates between consecutive toe-offs.

## ZVP cleaning (interactive edit + saved, 2026-10-12)
After raw detection a menu chooses how the ZVPs are cleaned (the chosen set feeds the detrend,
segmentation and **every** downstream step):
```
============== ZVP cleaning | Test N ==============
  Saved edits : FOUND (… left, … right ZVPs; saved <date>)   <- or "none yet"
   [Enter]  use the SAVED edits          (recommended)
    1       edit now  (revise / redo)    -> re-saves
    2       automatic detection          (no cleaning, not saved)
```
- **Default [Enter]** = reuse the saved edits for this test; the **first time** (no file yet) it drops
  straight into editing and saves, so next Enter just loads it.
- **Edit (1)** — a **separate figure per leg** (angle on top, `|gyro|`/`|acc|` norms + thresholds below,
  **every ZVP numbered**); **Left first, then Right**. Per leg: type indices to **REMOVE**, then times (s)
  to **ADD** (snapped to the nearest sample; `[]` = none), redraw, `done? y/n`. On entry it offers
  *"start from the saved edits?"* (default **y**). Result saved to
  `Results/Parameters Output/Test N/ZVP_Edits_TestN.xlsx` as **times** (robust to a step-3 re-run).
- **Automatic (2)** = raw detection minus the first `ZVP_SKIP_START` strides (the old no-clean path).
- Edit/saved modes **do not** apply `ZVP_SKIP_START` — you control the leading strides yourself.
> [!warning] After editing a step `.m`, run `clear all; clear functions; rehash` before re-running —
> MATLAB can otherwise execute a stale in-memory copy (raw ZVPs reappearing on [Enter] is this, not a save bug).

## Segmentation
Each signal is cut **ZVP → next ZVP**, both **normalized** (0–100 %, `NSEG = 200`) and
**time-domain** (raw samples, NaN-padded).
- Left signals use Left-foot ZVPs, right use Right-foot.
- **`ZVP_SKIP_START = 2`** — drops the **first two** strides per foot (start-of-test transients);
  applies to both feet and propagates to [[Step 5 - Obstacle Features]] via the saved ZVPs.
- **Partial trials (Awinda dropout):** every stride **column is kept**, including all-NaN ones. When the
  Awinda link dies mid-trial (see [[Heading Drift and De-drift]] / Test 103) the Dot still defines ZVPs
  for the whole trial, so late strides are **blank (NaN)** for Awinda/joint signals but present for the
  Dot. Keeping the columns keeps same-side signals aligned (per-stride terrain/role labels still line up);
  `mean`/`sd` use `omitnan`, so blanks are ignored, not propagated.

> [!important] Arms segment on the CONTRALATERAL foot
> Arm IMUs and shoulder/elbow joints swing with the opposite leg, so they are cut on the
> **opposite** foot's ZVPs (left arm → right foot, right arm → left foot) and inherit that foot's
> terrain / leading-trailing labels. See [[Session Changelog]].

## ZHC foot trajectory
Reconstructs each foot's 3D position per stride (double integration with a level-ground bias
solve). Needs the quaternion saved by [[Step 3 - Dot vs Awinda Sync]]. Height = Z.

## Outputs
- **`SegmentedParams_TestN.mat`** — `Seg` struct: `zvpL/zvpR`, `pct`, `timeAxis`, per-signal
  `.strides/.mean/.sd` (normalized) and `.stridesTime/...` (time), plus `Seg.zhc` foot positions.
- Figures: (1) ZVP detection, (2) stride viewer normalized, (3) stride viewer time-domain,
  (4) ZHC height per window, whole-trajectory 3D.

Prev: [[Step 3 - Dot vs Awinda Sync]] · Next: [[Step 5 - Obstacle Features]]
