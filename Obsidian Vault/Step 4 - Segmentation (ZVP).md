---
tags: [step, segmentation, gait-events]
aliases: [step4, step4_segmentation]
---

# Step 4 — Segmentation (ZVP)

**File:** `Analysis/step4_segmentation.m`
Detects gait events per side, cuts every signal into strides, and reconstructs the foot path.

## Gait events (ZVP = zero-velocity point / mid-stance)
Per side, from that side's **Dot foot IMU**:
- **Toe-offs** = inverted minima of foot **roll = Euler X**.
- **Candidates** = `|gyro| < OMEGA_THRESH` AND `|acc| < ACC_THRESH` (flat foot).
- One **ZVP** = midpoint of candidates between consecutive toe-offs.

## Segmentation
Each signal is cut **ZVP → next ZVP**, both **normalized** (0–100 %, `NSEG = 200`) and
**time-domain** (raw samples, NaN-padded).
- Left signals use Left-foot ZVPs, right use Right-foot.
- **`ZVP_SKIP_START = 2`** — drops the **first two** strides per foot (start-of-test transients);
  applies to both feet and propagates to [[Step 5 - Obstacle Features]] via the saved ZVPs.

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
