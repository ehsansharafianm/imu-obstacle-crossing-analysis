---
tags: [step, camera, segmentation, stride]
aliases: [step6, step6_segment_camera_trajectories]
---

# Step 6 — Camera Stride Segmentation

**File:** `Analysis/step6_segment_camera_trajectories.m`
Cuts the four camera foot markers into strides, on the **same ZVP boundaries** as the IMU, so camera
strides line up one-to-one with the IMU/joint strides.

## Inputs
- `CameraSynced_TestN.mat` (from [[Step 5 - Camera Sync and Viewers]]).
- `SegmentedParams_TestN.mat` (from [[Step 4 - Segmentation (ZVP)]]) — `zvpL`/`zvpR` and the ZHC foot path.

## What it does
- Segments L/R toe & heel (**obstacles excluded**): LEFT markers on `zvpL`, RIGHT on `zvpR`. Each
  marker's X/Y/Z is cut per stride and both **time-normalized** to `Seg.nseg` (0–100 % gait cycle)
  and kept **time-domain**. NaN-safe (interp over finite samples; all-NaN strides dropped).
- Overlays the step-4 **ZHC IMU foot height** as extra "markers" so the camera and IMU foot
  clearance can be compared per gait cycle.
- Two viewers (normalized 0–100 % and time-domain) with marker-checkbox + axis-selector (default Z),
  All-strides / Mean±SD display, and Save PNG.

## Outputs (`Results/Parameters Output/Test N/`)
- **`CameraSegmented_TestN.mat`** (`CamSeg.seg` per marker: normalized & time-domain strides +
  mean/SD).

> [!note] Coverage
> On test22, ~40 valid left strides and ~31 right — the rest had no camera data in that stride
> (the foot was out of the camera volume). The left clearance curve is physiological (heel peaks
> earlier, toe later).

Prev: [[Step 5 - Camera Sync and Viewers]] · next: [[Step 7 - Leading-Trailing Features (Camera)]]
