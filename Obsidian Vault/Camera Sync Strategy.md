---
tags: [camera, sync, strategy, discussion]
---

# Camera Sync Strategy

Design discussion for aligning the [[Camera Tracking (WorldViz PPT)]] data with the IMU pipeline
and segmenting it. Decisions here feed the eventual camera-integration code.

## Decision (chosen approach)
**Sync all three systems on the single deliberate left-leg lift at the *start* of the trial, then
rely on the camera's own timestamps.** Simplest workable approach; add an end-event later only if a
trial looks off.

## How the sync works
- IMUs already sync Awinda→Dot on the **first left-foot roll peak** (Euler X) — see [[Step 3 - Dot vs Awinda Sync]].
- The camera has **positions, not angles**, so its version of the same event is a **peak in the
  left-foot marker's vertical (Y) velocity**. Same physical lift, different observable.
- Align the camera to the same reference (Dot) using that event → one offset, one common timeline.
- **Prerequisite:** a **marker → body map** (which marker ID is the left foot). Not yet known
  (markers are just IDs 4/5/7/9/12/14).

## Drift analysis (from the Test 1 log)
- Camera's **own clock is steady**: rate by thirds = 59.99 / 59.91 / 59.95 Hz — no internal drift,
  just jitter. It runs at **~59.95 Hz**, not exactly 60.
- **Therefore use the real per-sample timestamps**, never an assumed exact 60 Hz (assuming 60 would
  accumulate ~60 ms / ~3–4 frames over a 72 s trial).
- **Camera vs IMU clock drift** can't be measured from the camera file alone (needs a paired trial).
  Bounded small (both ~60 Hz): worst case ~3–4 frames by the *end* of a long trial. Drift grows
  linearly from the sync point, so start/mid alignment is near-perfect.

### Why single start-event is enough (for now)
- Alignment is tightest where it's anchored (start).
- Segmentation events come from the IMU ZVPs, camera is only *sampled* at those times, so a few-frame
  tail residual is usually tolerable.
- Degrades gracefully: can add a start+end lift later to measure/correct drift with a linear time-warp.
- ⚠️ **Protect the start event:** the left-foot marker must be cleanly tracked *through* the opening
  lift (no dropout there), since there's no second event to catch a bad sync.

## Rate / resampling
- **No upsampling** (camera already ~60 Hz, unlike Awinda's 40→60).
- **But still resample** onto the uniform 60 Hz aligned grid via `interp1` using the real timestamps
  (the camera log is irregular: gaps 0.0166–0.066 s).

## Segmentation with missing data
Key idea: **don't detect gait events from the camera — reuse the IMU ZVPs** ([[Step 4 - Segmentation (ZVP)]]).
Cut the camera positions at the same ZVP stride boundaries on the shared grid.

Tiered dropout handling (mirrors the pipeline's NaN-pad + `omitnan`):
1. Resample onto the uniform 60 Hz aligned grid (real timestamps).
2. **Interpolate short gaps only** (≤ ~5 frames ≈ 83 ms; linear/pchip).
3. **Leave long gaps as NaN** (don't invent a dropout spanning a stride).
4. Segment at the IMU ZVPs; compute a per-stride **completeness %** and flag/exclude strides missing
   > ~20–30 %.

See dropout counts in [[Camera Tracking (WorldViz PPT)]] (~3 % missing, per-marker, occlusion).

## Open items
- Marker → body map + **Marker 5** identity (fixed reference vs lost marker).
- Coordinate-frame reconciliation — only needed later if *spatially* comparing camera height to the
  ZHC foot height ([[Step 4 - Segmentation (ZVP)]]); not needed for temporal segmentation.

Related: [[Camera Tracking (WorldViz PPT)]] · [[Data and Sensors]] · [[Session Changelog]]
