---
tags: [step, opensim]
aliases: [step1, step1_open_sense_pipeline]
---

# Step 1 — OpenSense IK

**File:** `Analysis/step1_open_sense_pipeline.m`
Raw Awinda → OpenSim orientations → calibrate model → IMU inverse kinematics.

## What it does
1. **`.mtb` → `.txt` auto-conversion** — if an Xsens `.mtb` is in `Data/Awinda IMUs/Test N/`,
   runs `xsens_awinda_converter.py` (Python `xsensdeviceapi`, `py -3.8`) to write the per-IMU
   `MT_*.txt` — no manual MT Manager export needed. Skips if the `.txt` are newer than the
   `.mtb`; no-op if there's no `.mtb`. Toggle via `convertMtb` / `pythonExe` / `converterScript`.
2. Reads each sensor's `Quat_q0..q3`, builds an OpenSim orientations `.sto`.
3. Calibrates the **Rajagopal 2015** model from the static pose (`IMUPlacer`), placing an
   IMU frame per body (`<body>_imu`). Mapping from `Setup/myIMUMappings.xml`.
4. Runs **`IMUInverseKinematicsTool`** → joint angles `ik_*.mot`.
5. Prints a per-sensor orientation-error summary (flags IMUs > 5°).

## Key settings
- `DATA_RATE = 40` Hz (Awinda).
- `freeCoords = true` — unclamps lower-limb coordinates and widens range (`freeRangeDeg = 180`)
  so IK isn't pinned at the model's joint limits (fixes the "flat 120°" artefact).
- Runs OpenSim in a short temp folder (long Google-Drive paths break native I/O), then copies
  results back to `Results/`.

## Inputs / outputs
- **In:** `Data/Awinda IMUs/Test N/` (`.mtb` and/or `MT_*.txt`), `Setup/myIMUMappings.xml`, `Model/Rajagopal_2015.osim`.
- **Out (`Results/OpenSim Outputs/Test N/`):** `STOFiles/*_orientations.sto`, `Rajagopal_2015_calibrated.osim`,
  `IKResults/ik_*.mot` (+ orientation errors), `IMU_IK_Setup.xml`, `opensim.log`.

## Notes from the work
- **12 IMUs** now (arms added). Model already had arm bodies; OpenSense builds their IMU frames
  during calibration — no model edit needed. See [[Session Changelog]].
- The **Awinda `PacketCounter` is 16-bit and can roll over** mid-trial; that broke step 3 on
  Test 13 and is now unwrapped there ([[Step 3 - Dot vs Awinda Sync]]). Step 1 is immune because
  it builds time from the sample index, not the counter.

Next: [[Step 2 - Joint Angle Viewer]] · back to [[Pipeline Workflow]]
