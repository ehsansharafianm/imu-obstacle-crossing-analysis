---
tags: [reference, glossary, conventions]
---

# Conventions and Glossary

## Axes & units
- **IMU Euler** stored `[Z X Y]` (deg). The pipeline uses the **X** column as the working signal
  (foot roll for gait events in [[Step 4 - Segmentation (ZVP)]]).
- **Camera (PPT):** **Y = vertical (up)**, metres, Y-up right-handed ([[Camera Tracking (WorldViz PPT)]]).
- **OpenSim WBAM:** vector in the model **Ground** frame; ZHC heights in metres.
- Rotational coords in **degrees** in `.mot`; converted to **radians** for the OpenSim API.

## Sampling rates
- Awinda 40 Hz → upsampled to 60 Hz · Dot 60 Hz · Camera ~60 Hz logged (240 FPS capture).
- Shared analysis grid = **60 Hz**. See [[Data and Sensors]].

## Terrain labels
`Level_Walk`, `Height1_Depth1` … `Height3_Depth2` (obstacle height × depth). Logger short form
`H<n>_D<m>` → `Height<n>_Depth<m>`.

## Terms
- **ZVP** — zero-velocity point (mid-stance); stride-boundary event ([[Step 4 - Segmentation (ZVP)]]).
- **ZHC** — the foot-trajectory reconstruction method (zero-height/zero-velocity constrained double
  integration), giving foot position & clearance per stride.
- **Leading / Trailing** — which limb crosses the obstacle first / second (from the Logger).
- **Contralateral arm rule** — arm signals segment on the **opposite** foot's ZVPs, since arm swing
  is coupled to the opposite leg ([[Step 4 - Segmentation (ZVP)]], [[Step 5 - Obstacle Features]]).
- **WBAM** — whole-body angular momentum about the COM; a dynamic-balance measure ([[Step X - Angular Momentum]]).
- **FeatureLog** — Dot per-foot CSV of labelled crossing windows (height, stride, packets).
- **Logger** — Dot text log naming the leading leg per crossing with a packet range.

## Model joints (Rajagopal 2015)
- Shoulder `acromial` → `arm_flex`, `arm_add`, `arm_rot` · Elbow `elbow` → `elbow_flex`
- Forearm IMU → **ulna**; hip/knee/ankle as usual. Kept in analysis: hip/knee/ankle + `arm_flex`/`arm_add`/`elbow_flex`
  (dropped: `hip_rotation`, knee `beta`, `arm_rot`, `pro_sup`, wrist).

Back to [[Home]]
