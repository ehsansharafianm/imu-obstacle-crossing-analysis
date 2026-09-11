---
tags: [changelog, summary]
---

# Session Changelog

Summary of the work done on the project (most impactful first). Dates are approximate to the
2026 working sessions.

## ★ Latest (2026-09) — camera-driven labelling: step 5 removed, step 8 rewritten, step 6 sync fixed
Study goal captured in [[Study Rationale and Goal]].
- **Labelling now comes from the camera.** The app terrain labels + Dot "Logger" leading-leg log were
  unreliable, so **step 5 was deleted**. Obstacle type + leading/trailing per crossing now come from the
  **CV-side step 3 crossings** (`testN_crossings.xlsx`), which the CV pipeline writes to **both** the CV
  results and the IMU `Results/Parameters Output/Test N/`. Terrain groups are now `W{width}_H{height}`
  (width first), e.g. `W2_H1`.
- **[[Step 8 - Leading-Trailing Features (Camera)]] rewritten** to be camera-driven: it maps each
  crossing's y=0 time to the IMU clock (`t_cam + step-6 shift`) and tags the **stride the crossing lands
  in** — leading foot's stride (`lead_cross_s`) = Leading, trailing foot's stride = Trailing — then runs
  the same viewers/export as before. **Level_Walk** still comes from the app FeatureLog (`Ground_Truth`);
  the Logger log is no longer read. Verified on test101 (55 crossings mapped, 0 unmatched).
- **Step 6 sync bug fixed.** Auto-sync was locking onto walking/crossings, not the leg-raise gesture:
  (a) obstacle crossings reach the same L_toe height as the raises, and (b) the IMU sign-picker chose the
  −EX *walking* side (walking −EX ≈ −70° > the raise's +EX ≈ +55°). Now: the camera **start raise** is
  taken **before the first crossing** (from step 3), the **end raise** is the last tall peak, and the IMU
  picks the foot-X **sign that brackets the trial** (raises appear only at start+end). Crucially the raise
  threshold is now set from the **raise level (median of the tallest peaks)**, not a fixed 45° floor — the
  first raise (43°) was falling just under 45° and being skipped, which caused a residual. Alignment =
  single shift on the **first peak**; the **final peak** measures drift. On test102: shift +20.1 s →
  **−6.00 s**, drift −34.9 s → **−0.004 s (0.000 %)** — the clocks are essentially locked (no rate
  mismatch after all; it was the missed first peak). **test101 IMUs are corrupt — benchmark on test102.**
- **CV matlab files renamed** to a numbered pipeline: `step1_plot_trajectory`, `step2_refine_trajectory`
  (adds an obstacle >60 cm height cut), `step3_detect_crossings` (guided trial-by-trial obstacle
  labelling + total-time X/Y/Z overview with per-cycle #/lead→trail labels).

## ★ (2026-09) — IMU heading drift diagnosed & fixed
Full write-up in [[Heading Drift and De-drift]]. The September trials (21/22/24/101) had joint angles
winding hundreds–thousands of degrees. Proved the cause is **IMU heading (yaw) drift** baked into the
Awinda quaternions (magnetometer unreliable in the lab), **not** OpenSim — the flexion/tilt channel
you see in step 3 is gravity-clean, but the hidden heading channel drifts ~800 deg and OpenSim turns
it into winding joints. Recording-side VRU won't persist (MTw2 fw 4.6.0) and offline reprocess can't
recover heading, so the fix is post-hoc: an **anatomical heading-lock** — freeze each limb segment's
heading to a clean base (legs→pelvis, arms→torso) at t=0 (knees/ankles are hinges → limbs share one
heading), removing differential drift while keeping gravity-anchored tilt. Validated on Test 101
(both legs): every IMU roughly halved, no left↔right flip, winding gone. Integrated into **step1**
(`y/n` de-drift → `IKResults_dedrift` + BEFORE→AFTER table); **step2/step3** have matching `y/n` so
step4/5/6/8/9 inherit; targeted `ankle_angle_l` cleanup added in step2/step3. `stepX` still TODO.

## ★ Latest (2026-09) — step 6 manual camera sync
[[Step 6 - Camera Sync and Viewers]] now asks **auto (default, Enter) or manual** sync. Manual shows a
**preview** of both signals, prints the auto-detected peaks, and you type the **IMU peak time** and
**camera peak time** (Enter accepts the auto value) → it computes `offset = IMU − camera` for you and
reports the end residual as a self-check. Auto path is unchanged.

## 1. Arm IMUs + shoulder/elbow joints (steps 1–5)
Added **4 arm IMUs** (upper arm + forearm, both sides) to capture **shoulder & elbow** angles.
- `Setup/myIMUMappings.xml` — 4 new sensors: upper arms → `humerus_r/l_imu`, forearms → `ulna_r/l_imu`
  (forearm on the **ulna** so the elbow angle is clean). IDs in [[Data and Sensors]].
- No model edit needed — OpenSense builds the frames during calibration.
- [[Step 3 - Dot vs Awinda Sync]] joint filter now keeps `arm_flex`/`arm_add`/`elbow_flex`
  (drops `arm_rot`, like `hip_rotation`); arm IMUs carried through + an "Awinda IMUs Arms" sheet.
- [[Step 2 - Joint Angle Viewer]] shows arm joints by default.
- Steps 4 & 5 were already generic → arms flow through automatically.

## 2. `.mtb` → `.txt` auto-conversion in step 1
[[Step 1 - OpenSense IK]] now runs `xsens_awinda_converter.py` (Python `xsensdeviceapi`, `py -3.8`)
on the `.mtb` in the test folder — no manual MT Manager export. Settings: `convertMtb`,
`pythonExe`, `converterScript`, `forceConvert`. Backward-compatible (uses existing `.txt` if no `.mtb`).

## 3. Awinda PacketCounter rollover fix (step 3)
The 16-bit Awinda `PacketCounter` wraps at 65536. **Test 13** started at 57954 and wrapped through 0,
which made packet-derived time go negative and the 60 Hz resample grid empty (crash). Fixed with
`unwrapCounter(pkt, 65536)` in [[Step 3 - Dot vs Awinda Sync]]. General robustness fix.

## 4. Drop the first two strides (step 4)
`ZVP_SKIP_START` set **1 → 2** — the first two start-of-test strides per foot are excluded from
segmentation, figures, and calculations. Propagates to [[Step 5 - Obstacle Features]] via saved ZVPs.

## 5. Contralateral arm segmentation (steps 4 & 5)
Arm IMUs/joints now segment on the **opposite** foot's ZVPs (arm swing is coupled to the opposite
leg) and inherit that foot's terrain / leading-trailing labels; `.side` still names the physical arm.
Verified in [[Step 5 - Obstacle Features]]: no duplication, column counts match labels.

## 6. Step 6 — Angular momentum (new)
Created [[Step X - Angular Momentum]] — whole-body + segmental (Arms/Legs/Trunk) angular momentum
via Simbody + a manual per-segment sum (mutually validated), with an interactive toggle viewer,
default vs prompted body features, `.mat`/`.xlsx` export, and `tic/toc` timing. Static overview
figure removed; entity labels black.

## 7. Camera system — WorldViz PPT (new, third stream)
Added [[Camera Tracking (WorldViz PPT)]] test viewer (`test_camera_markers.m`) — **three viewers**,
each with per-marker toggles and Line/Scatter/Both style:
1. 3D trajectory (**Y drawn vertical**), 2. positions vs time (X/Y/Z), 3. **vertical Y vs horizontal
XZ displacement** (2D side view).
Findings:
- Log is **~60 Hz** (not the 240 FPS capture rate); camera clock steady (~59.95 Hz, no internal drift).
- Markers have **unequal counts / dropouts** (~3 % missing, occlusion).

## 8. Camera sync & segmentation strategy (decided)
See [[Camera Sync Strategy]]. Sync all three systems on the **start left-leg lift** (camera event =
left-foot vertical-velocity peak) and rely on the camera's **real timestamps**; resample onto the
uniform 60 Hz grid (no upsampling needed); **segment the camera at the IMU ZVPs**; interpolate short
dropouts only, NaN the long ones, flag low-completeness strides. Next concrete step: the
**marker→body map**.

## 9. Camera pipeline realized — steps 6–9 (new) 🎉
The camera is fully integrated as a numbered pipeline. See [[Camera Pipeline - Achievements]].
- [[Step 6 - Camera Sync and Viewers]] — sync camera markers to the 60 Hz IMU grid via the 3× left-leg
  raise gesture (single shift, ~0 drift), then angles / trajectories-vs-time / 3D viewers with per-leg
  gait-event overlays (ZVP, toe-off, heel-strike), a foot-angle sanity overlay, and auto-fit.
- [[Step 7 - Camera Stride Segmentation]] — camera foot markers cut on the step-4 ZVPs (+ ZHC overlay);
  saves `CameraSegmented_TestN.mat`.
- [[Step 8 - Leading-Trailing Features (Camera)]] — step-5 features extended with the camera; saves
  `SegTrajectories_WithCamera_TestN.mat` (`S5.camera.*`).
- [[Step 9 - Crossing Parameters]] — foot placement (lift/landing) + height & **min** clearance per
  crossing; saves `CrossingParams_TestN.mat/.xlsx` + arc/param/clearance figures. Prompts for leg length.

## 10. CV-side trajectory refinement (new)
`refine_trajectory.m` (CV repo) cleans the raw reconstructed workbook → `testN_trajectory_refined.xlsx`
(despike out-of-volume / non-negative height, short-gap fill, smoothing; time/sampling untouched) and
writes it into `Data/Camera CV/Test N/`. Step 6 prefers the `*_refined` file. `plot_trajectory` and
`refine_trajectory` are scripts (prompt for the test number).

## 11. Gait events saved in step 4
[[Step 4 - Segmentation (ZVP)]] now also saves toe-off / heel-strike sample indices
(`Seg.toeL/hsL/toeR/hsR`) next to the ZVPs, so the camera viewers can overlay them per leg.

## 12. Numbering note
The angular-momentum add-on is `stepX_angular_momentum.m` → renamed here to [[Step X - Angular Momentum]]
so steps **6–9** name the camera pipeline.

## Housekeeping / notes
- Steps 6–9 and step 4's change are **committed & pushed** to the analysis repo
  (`imu-obstacle-crossing-analysis`); `refine_trajectory` / `plot_trajectory` to the CV repo
  (`obstacle-crossing-computer-vision`). This vault update is committed with them.
- The large binary `.mat`/`.xlsx` outputs and `Data/`/`Results/` blobs are generally left uncommitted
  (history-bloat risk) — see [[Outputs and File Formats]].

Back to [[Home]]
