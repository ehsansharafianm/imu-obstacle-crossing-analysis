---
tags: [camera, ppt, worldviz, in-progress]
aliases: [camera, PPT, test_camera_markers]
---

# Camera Tracking (WorldViz PPT)

The **third measurement system** — optical marker position tracking
([WorldViz PPT](https://www.worldviz.com/virtual-reality-motion-tracking)). 6–8 markers per study.
Currently a **standalone test viewer**, not yet integrated into the pipeline.

**File:** `Analysis/test_camera_markers.m` (a system test, not a numbered step).

## Data format
`Data/Camera/Test N/ppt_multi_tracking_log.csv` — long/tidy, one row per marker per timestamp:
```
Timestamp, Marker_ID, VRPN_Index, X, Y, Z
```
- **Y = vertical (up)**, positions in **metres** (WorldViz Y-up convention).
- Sample (Test 1): 6 markers → IDs `4, 5, 7, 9, 12, 14`. Marker 5 is static & offset (a fixed
  reference or a parked/lost marker).

## Frequency  ⭐
Cameras **capture at 240 FPS**, but the **logged CSV is ~60 Hz**:
- 4,359 unique timestamps over 72.69 s → **60.0 Hz**; median frame gap 0.01668 s = `1/60`.
- (If 240 Hz were wanted in the file, that's a WorldViz logger setting.)
- Convenient: matches the Dot / pipeline 60 Hz grid ([[Data and Sensors]]).

## Missing data
Markers drop out (occlusion) at **different** times, so counts differ:

| Marker | Missing frames | % |
|--------|----------------|---|
| 14 | 9 | 0.2 |
| 12 | 61 | 1.4 |
| 5 | 85 | 2.0 |
| 7 | 156 | 3.6 |
| 9 | 214 | 4.9 |
| 4 | 267 | 6.1 |

~792 of 26,154 possible samples missing (~3 %). No gap-filling applied yet — inspect with scatter.

## The test viewer
**Three figures**, each with **per-marker checkbox toggles** and a **Line / Scatter / Both** style
selector (default Both; scatter = one dot per sample, so dropouts show as missing dots):
1. **3D trajectory** — all markers in one `plot3`, drawn as `(X, Z, Y)` so **Y appears vertical**;
   circle = start, square = end; mouse-rotatable, `axis equal`.
2. **Positions vs time** — X / Y / Z per marker vs time, axis checkboxes + marker toggles.
3. **Vertical vs horizontal displacement (2D side view)** — Y vs `d = sqrt((X-X0)²+(Z-Z0)²)`
   (horizontal displacement in the XZ plane from each marker's start). The "Y per XZ" elevation view.

## Sync & segmentation
See [[Camera Sync Strategy]] — decision: sync all three systems on the **start left-leg lift** and
rely on the camera's real timestamps; segment the camera at the **IMU ZVPs**; interpolate only short
dropouts, NaN the long ones.

## Open decisions
- **Marker → body map** (which ID is the left foot, needed for the sync event) + **Marker 5** identity
  (fixed reference vs lost marker).
- Whether to check the WorldViz logger for the full 240 Hz.

Related: [[Data and Sensors]] · [[Session Changelog]]
