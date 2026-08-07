---
tags: [workflow, howto]
---

# Pipeline Workflow

Run all scripts **from the `Analysis/` folder**. Each prompts for a **Test number** `N`.

## Order & dependencies
```
step1  ->  step2                         (OpenSim joint angles, Awinda only)
step3  ->  step4  ->  step5              (comparison -> segmentation -> features)
                        \-> step6         (angular momentum; reads step-1 IK + optionally step 4/5)
```
- [[Step 1 - OpenSense IK]] before [[Step 2 - Joint Angle Viewer]] and before [[Step 3 - Dot vs Awinda Sync]].
- [[Step 3 - Dot vs Awinda Sync]] before [[Step 4 - Segmentation (ZVP)]] (reads `AllData_TestN.mat`).
- [[Step 4 - Segmentation (ZVP)]] before [[Step 5 - Obstacle Features]] (reads `SegmentedParams_TestN.mat`).
- [[Step 6 - Angular Momentum]] is standalone — needs step 1's calibrated model + IK `.mot`.

## One-line purpose of each step
| Step | Purpose |
|------|---------|
| [[Step 1 - OpenSense IK]] | `.mtb`→`.txt`, calibrate model, run IMU inverse kinematics |
| [[Step 2 - Joint Angle Viewer]] | interactive viewer of the IK joint angles |
| [[Step 3 - Dot vs Awinda Sync]] | sync both systems to 60 Hz, export `AllData` (mat/xlsx) |
| [[Step 4 - Segmentation (ZVP)]] | detect ZVP gait events, cut strides, reconstruct foot path |
| [[Step 5 - Obstacle Features]] | label leading/trailing + terrain, foot clearance, export |
| [[Step 6 - Angular Momentum]] | whole-body + segmental angular momentum |

## Requirements
- **OpenSim 4.x MATLAB API** (`org.opensim.modeling.*`) — steps 1 & 6.
- **Sensor Fusion & Tracking Toolbox** (`quaternion`/`eulerd`) — step 3.
- **Signal Processing Toolbox** (`findpeaks`, `butter`/`filtfilt`) — steps 4 & 6.
- **Python + Xsens `xsensdeviceapi`** (`py -3.8`) — only for step 1's `.mtb`→`.txt` auto-conversion.

## Not-yet-integrated
- [[Camera Tracking (WorldViz PPT)]] — currently a standalone test viewer (`test_camera_markers.m`), not wired into the pipeline yet.

Related: [[Outputs and File Formats]] · [[Session Changelog]]
