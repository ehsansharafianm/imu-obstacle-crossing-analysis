---
tags: [imu, drift, opensim, dedrift, methods]
aliases: [heading drift, de-drift, dedrift, anatomical heading-lock]
---

# Heading Drift and De-drift

How we diagnosed and fixed the **IMU heading drift** that wrecked the joint angles in the
September 2026 trials, and how the fix is wired into the pipeline. See also
[[Step 1 - OpenSense IK]], [[Step 2 - Joint Angle Viewer]], [[Step 3 - Dot vs Awinda Sync]].

## The problem
In several September trials (**Test 21, 22, 24, 101**) the lower-limb joint angles from OpenSim
wound through **hundreds to thousands of degrees** over a trial (e.g. `hip_flexion_r` spanning
1700-3500 deg). The right leg was worst; on the long trial **101 (15 min) both legs** drifted.

## Origin — it is the IMU heading, NOT OpenSim
Proven straight from the raw Awinda quaternions (OpenSim never involved). For a drifting thigh IMU:
- **Tilt** (angle from vertical, gravity-anchored) drift ≈ **0.1 deg** — clean.
- **Heading** (yaw about vertical), measured relative to the pelvis, drift ≈ **800 deg**.

So the sensor is fine in the channel you *see* in step 3 (the flexion / Euler-X / tilt channel, which
gravity keeps honest) but has huge drift in the **heading** channel, which step 3 does not plot.
A joint needs the full 3-D orientation of two segments, so OpenSim faithfully turns the hidden
heading drift into winding joints. **OpenSim is the messenger, not the cause.** The root cause is the
Awinda onboard fusion letting heading drift because the **magnetometer is unreliable** in the lab
(disturbed field; drift grows ~20-30 deg/min and is re-excited at every sharp turn).

Quality gate: the OpenSim orientation-tracking error (`IKResults/*_orientationErrors.sto`) is the
trustworthy per-IMU metric. Healthy IMU < ~10 deg mean; the Sept legs were 20-55 deg.

## What did NOT work (and why)
- **Recording-side VRU profile**: the MTw2 (fw 4.6.0) will not *persist* the VRU filter setting - it
  reverts to `human` on reopen. Manual VRU reprocess in MT Manager changed nothing.
- **Offline reprocess (XDA / step1)**: the `.mtb` stores the finished onboard orientation; setting
  VRU/AHS/ICC + `restartFilter()` gives byte-identical output. A DIY no-mag re-integration drifted
  15,000 deg. Heading is unobservable offline without an external reference (mag corrupt, no camera
  in the IMU pipeline). **Conclusion: fix must be at capture, or post-hoc from a constraint.**
- **Camera-aided**: rejected by choice (we did not use the optical markers).
- **Pelvis-relative slow-trend de-drift**: worked for a single badly-drifting segment but (a) used a
  confounded heading metric, (b) the whole-body IK coupling shifted the *uncorrected* segments, so it
  flipped the problem left<->right on Test 101.

## The fix that works — Anatomical heading-lock
A **knee / ankle / elbow is a hinge**: the segments of one limb physically must share ONE heading
(yaw about vertical). So we **freeze each limb segment's heading relative to a clean base** at its
t=0 (calibration) value:
- legs -> **pelvis**, arms -> **torso**;
- `alpha(t) = (yaw_ref - yaw_seg) - (same at t0)`, applied as a **world-Z pre-rotation** of the
  segment quaternion. A vertical rotation changes only heading and **preserves tilt exactly**;
  `alpha(t0)=0` keeps the calibration frame.
- Removes the differential heading **drift**; the residual whole-limb heading falls into the rotation
  DOFs (**hip_rotation / arm_rot**) which are discarded anyway -> hip_flexion, knee, ankle, arm_flex,
  elbow come out clean. IMU-only, per-limb (handles both-legs-drift), no reference/gate guessing.

**Critical detail:** use the **swing-twist** heading `2*atan2(qz,qw)`, NOT Tait-Bryan yaw - the latter
gimbal-locks when the shank pitches through vertical each swing (gave 37,000 deg).

### Validated (Test 101, worst case: 15 min, both legs)
Every segment roughly **halved**, both sides coherently, no left<->right flip:
femur_r 54->16, tibia_r 40->14, calcn_r 25->12, femur_l 35->16, tibia_l 22->13, calcn_l 18->15,
arms 26->10 / 17->11. The **winding is gone** (joints bounded / gait-shaped). 101 lands ~12-16 deg
(not <10) because it is the hardest trial; one-sided / shorter trials (e.g. 23) go under 10.
**Caveat:** per-turn **max** error still spikes (30-50 deg) - keep analysis on straight-walking
strides, not the turns.

## How it is wired (pipeline)
- **[[Step 1 - OpenSense IK]]**: a `y/n` prompt "Apply heading de-drift + re-run IK?". When **y**,
  step1 does the anatomical lock and re-runs IK, writing `IKResults_dedrift/` (raw `IKResults/`
  untouched) and printing a BEFORE->AFTER tracking-error table.
- **[[Step 2 - Joint Angle Viewer]]** and **[[Step 3 - Dot vs Awinda Sync]]**: matching
  "use de-drifted?" `y/n`. step3 `y` pushes corrected joints into `AllData`, so **step4/5/6/8/9
  inherit automatically** (they read `AllData`). step4 gait events use the Dot foot IMU, so
  segmentation was never affected by heading drift.
- **stepX (angular momentum)** reads `ik_*.mot` directly -> still needs a de-drift toggle (TODO).
- **Rule:** pick de-drift once and stay consistent (y in step1 + step3, and stepX once wired).

### Targeted joint cleanup
`ankle_angle_l` still showed baseline drift after the lock -> a per-coordinate cleanup was added in
step2 & step3 (`CLEAN_JOINTS = {'ankle_angle_l'}`): detrend on (signal-honest), optional low-pass /
clamp off (cosmetic).

## Update (2026-09-11) — joint-level cleanup + the hard limits
- **ZVP baseline detrend** in [[Step 4 - Segmentation (ZVP)]] (default ON): anchors each joint at its
  mid-stance baseline (first strides) and subtracts the slow wander; re-saves `AllData` so step5-8
  inherit. Fixes a **baseline shift** (e.g. the Test 101 ankles). Does NOT fix posture-dependent drift.
- **Test 102 — the reference itself drifts.** The heading-lock references all legs to the pelvis; on
  Test 102 the pelvis IMU drifts ~12°, so the correction copies the pelvis drift into the legs (the
  left leg even got *worse*). The residual is **posture-dependent** (larger in flexion, ~flat at
  mid-stance), so the ZVP baseline anchor can't reach it. **Trials with a clean pelvis (101) are the
  trustworthy ones.**
- **step7 metrics now all-IMU (ZHC); camera = validation:** height = peak Z, stride = net-XY per ZVP
  cycle; camera peak-Z kept as `heightCam`. Dot-app numbers retired.

## Limitations (for the paper)
- **Absolute joint angles are drift-limited** on the badly-drifting trials. Heading is *unobservable*
  from the IMU alone without an absolute reference (magnetometer corrupted; camera not used inside the
  IMU pipeline), so the residual can't be fully removed — it's the **IMU-only floor**, not lack of
  effort. Typical IMU-IK accuracy is ~5–10° even at best.
- **What is clean / reportable:**
  - **Foot clearance** — from the **camera** (drift-free, gold standard).
  - **Joint ROM / excursion** = **max − min per stride** — *drift-immune* (within one ~1 s stride the
    drift is ~0.5°, so it cancels in max−min). The standard obstacle-crossing joint measure.
  - **Stride length** — from ZHC (per-stride, ZUPT-bounded).
  - **IMU-vs-camera agreement** (`heightCam` vs ZHC height) — a methods contribution.
- **Recommendation:** lead with the clean metrics (camera clearance, joint ROM, stride length);
  report absolute peak angles as *secondary* with the IMU-accuracy caveat; present IMU-vs-camera
  agreement as a result, not a weakness. **VRU/AHS at capture** would prevent the drift but does not
  persist on the current MTw2 firmware — open item with Movella (see [[Lab Checklist - IMU Drift]]).

## Related
[[Session Changelog]] · [[Data and Sensors]] · [[Step 5 - Camera Sync and Viewers]] · [[Home]]
