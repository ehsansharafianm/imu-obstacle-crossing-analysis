---
tags: [reference, outputs, formats]
---

# Outputs and File Formats

Where each step writes, and how to read it. Everything is per `Test N`.

## Results tree
```
Results/
├── OpenSim Outputs/Test N/
│   ├── STOFiles/*_orientations.sto        (step 1)
│   ├── Rajagopal_2015_calibrated.osim     (step 1)
│   ├── IKResults/ik_*.mot (+ errors)      (step 1)
│   ├── IMU_IK_Setup.xml, opensim.log      (step 1)
│   └── Figures/                           (step 2)
└── Parameters Output/Test N/
    ├── AllData_TestN.mat / .xlsx          (step 3)
    ├── SegmentedParams_TestN.mat          (step 4)
    ├── WindowFeatures_SideBased_TestN.xlsx(step 5)
    ├── SegTrajectories_SideBased_TestN.mat(step 5)
    └── AngularMomentum_TestN.mat / .xlsx  (step 5)
```

## Key MATLAB structs
- **`Data`** (`AllData_TestN.mat`, [[Step 3 - Dot vs Awinda Sync]]) — `.time`, `.fs`, `.sync`,
  `.imu(k)` (`.label/.body/.system/.euler_ZXY_deg/.packet/.acc/.gyro/.quat`), `.joints`.
- **`Seg`** (`SegmentedParams_TestN.mat`, [[Step 4 - Segmentation (ZVP)]]) — `.zvpL/.zvpR`, `.pct`,
  `.timeAxis`, `.signal(k)` (strides + mean/sd, normalized & time), `.zhc` foot positions.
- **`S5`** (`SegTrajectories_SideBased_TestN.mat`, [[Step 5 - Obstacle Features]]) — `.signal(k)`
  (`.Y/.Yt/.side/.terrain/.role/.cycle`), `.zhc` height trajectories, `.zhc.all` per-cycle table,
  `.Feat`, `.log`.
- **`AM`** (`AngularMomentum_TestN.mat`, [[Step X - Angular Momentum]]) — whole-body
  `.H_model/.H_subject/.H_norm/.Hmag`, `.seg` (per-segment), `.group` (Arms/Legs/Trunk).

## Conventions
- IMU orientation stored as Euler **`[Z X Y]`** (deg); the pipeline plots/segments the **X** column.
- Angles in degrees; ZHC heights & camera positions in metres.
- See [[Conventions and Glossary]].

> [!warning] Binary outputs in git
> The `.mat`/`.xlsx` results are large binaries that get rewritten on every re-run. They are
> version-controlled in this repo, which bloats history over time — consider Git LFS if it grows.

Related: [[Pipeline Workflow]]
