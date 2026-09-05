---
tags: [workflow, howto]
---

# Pipeline Workflow

Run all scripts **from the `Analysis/` folder**. Each prompts for a **Test number** `N`.

## Order & dependencies
```
step1 -> step2                                  (OpenSim joint angles, Awinda only)
step3 -> step4 -> step5                          (comparison -> segmentation -> features)
                    \-> step8 -> step9           (leading/trailing + camera -> crossing parameters)
         step6 -> step7 -> step8/step9           (camera: sync+view -> segment -> features/params)
stepX  (angular momentum; standalone, reads step-1 IK)
```
IMU: [[Step 1 - OpenSense IK]] → [[Step 2 - Joint Angle Viewer]] / [[Step 3 - Dot vs Awinda Sync]] →
[[Step 4 - Segmentation (ZVP)]] → [[Step 5 - Obstacle Features]].
Camera: **first refine** the CV workbook (`refine_trajectory` in the CV repo → `*_refined.xlsx` into
`Data/Camera CV/Test N/`), then [[Step 6 - Camera Sync and Viewers]] (needs `AllData` from step 3) →
[[Step 7 - Camera Stride Segmentation]] (needs `SegmentedParams` from step 4) →
[[Step 8 - Leading-Trailing Features (Camera)]] (needs FeatureLogs+Logger, `CameraSynced`) →
[[Step 9 - Crossing Parameters]] (needs `CameraSynced`, `SegmentedParams`, step-8 `S5`; prompts for leg length).
[[Step X - Angular Momentum]] is standalone — needs step 1's calibrated model + IK `.mot`.

## One-line purpose of each step
| Step | Purpose |
|------|---------|
| [[Step 1 - OpenSense IK]] | `.mtb`→`.txt`, calibrate model, run IMU inverse kinematics |
| [[Step 2 - Joint Angle Viewer]] | interactive viewer of the IK joint angles |
| [[Step 3 - Dot vs Awinda Sync]] | sync both systems to 60 Hz, export `AllData` (mat/xlsx) |
| [[Step 4 - Segmentation (ZVP)]] | detect ZVP gait events, cut strides, reconstruct foot path |
| [[Step 5 - Obstacle Features]] | label leading/trailing + terrain, foot clearance, export |
| [[Step 6 - Camera Sync and Viewers]] | sync camera markers to the 60 Hz IMU grid; angles/traj/3D viewers |
| [[Step 7 - Camera Stride Segmentation]] | cut camera foot markers into strides on the IMU ZVPs |
| [[Step 8 - Leading-Trailing Features (Camera)]] | step-5 features + camera, by side & leading/trailing |
| [[Step 9 - Crossing Parameters]] | foot placement + height/min clearance per crossing |
| [[Step X - Angular Momentum]] | whole-body + segmental angular momentum (standalone) |

## Requirements
- **OpenSim 4.x MATLAB API** (`org.opensim.modeling.*`) — steps 1 & 6.
- **Sensor Fusion & Tracking Toolbox** (`quaternion`/`eulerd`) — step 3.
- **Signal Processing Toolbox** (`findpeaks`, `butter`/`filtfilt`) — steps 4 & 6.
- **Python + Xsens `xsensdeviceapi`** (`py -3.8`) — only for step 1's `.mtb`→`.txt` auto-conversion.

## Camera integration ✅
The camera is fully wired in as **steps 6–9** — see [[Camera Pipeline - Achievements]]. Refine the CV
workbook first (`refine_trajectory` in the CV repo). `test_camera_markers.m` remains as a quick
standalone viewer.

Related: [[Outputs and File Formats]] · [[Session Changelog]] · [[Camera Pipeline - Achievements]]
