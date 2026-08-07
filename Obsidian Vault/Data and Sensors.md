---
tags: [data, sensors, reference]
---

# Data and Sensors

Three synchronized measurement systems. Rates matter for [[Step 3 - Dot vs Awinda Sync]].

| System | Sensors | Native rate | Role |
|--------|---------|-------------|------|
| **Xsens Awinda** | 12 IMUs | **40 Hz** | → OpenSim IK ([[Step 1 - OpenSense IK]]) |
| **Movella Dot** | 6 IMUs (lower limb) | **60 Hz** | gait events + foot trajectory ([[Step 4 - Segmentation (ZVP)]]) |
| **WorldViz PPT** | 6–8 markers | 240 FPS capture / **~60 Hz logged** | optical position ([[Camera Tracking (WorldViz PPT)]]) |

> [!tip] Rates line up at 60 Hz
> Dot is 60 Hz, Awinda is upsampled 40→60 Hz, and the camera log is ~60 Hz — so everything
> can share a 60 Hz grid.

## Sensor map (Awinda ID → body → Dot)

| Body | Awinda ID | Dot | Model IMU frame |
|------|-----------|-----|-----------------|
| Sternum | 00B4AB26 | – | `torso_imu` |
| Pelvis | 00B4AB22 | – | `pelvis_imu` |
| Left Foot | 00B4AB23 | IMU1 | `calcn_l_imu` |
| Right Foot | 00B4AB29 | IMU2 | `calcn_r_imu` |
| Left Thigh | 00B4AB2D | IMU3 | `femur_l_imu` |
| Right Thigh | 00B4AB2B | IMU4 | `femur_r_imu` |
| Left Shank | 00B4AB25 | IMU5 | `tibia_l_imu` |
| Right Shank | 00B4AB27 | IMU6 | `tibia_r_imu` |
| Left Upper Arm | 00B4AB2E | – | `humerus_l_imu` |
| Right Upper Arm | 00B4AB31 | – | `humerus_r_imu` |
| Left Forearm | 00B4AB28 | – | `ulna_l_imu` |
| Right Forearm | 00B4AB2F | – | `ulna_r_imu` |

The **arm sensors are Awinda-only** (no Dot counterpart). Forearm IMUs map to the **ulna**
(the elbow joint is humerus→ulna, giving a clean elbow angle). See [[Session Changelog]].

## Raw data layout
```
Data/
├── Awinda IMUs/Test N/   MT_*.txt  (+ the .mtb, auto-converted in step 1)
├── Dot IMUs/Test N/       IMU1..6_*.csv, FeatureLog_IMU1/2_*.csv, "Logger ... .txt"
└── Camera/Test N/         ppt_multi_tracking_log.csv
```

## File formats
- **Awinda `.txt`** — Xsens MT columns incl. `Quat_q0..q3`; 16-bit `PacketCounter` (can roll over — handled in [[Step 3 - Dot vs Awinda Sync]]).
- **Dot `.csv`** — `PacketCounter`, `Acc_*`, `Gyr_*`, `Quat_*`; streaming IMUs carry a terrain packet offset (mod 1e6).
- **Camera `.csv`** — long format `Timestamp, Marker_ID, VRPN_Index, X, Y, Z`; **Y = vertical**, metres, has dropouts. See [[Camera Tracking (WorldViz PPT)]].

Related: [[Conventions and Glossary]] · [[Outputs and File Formats]]
