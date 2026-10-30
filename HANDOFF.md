# Project Handoff — IMU Obstacle-Crossing Analysis

Paste this into a new Claude Code chat to bring it up to speed. Last updated 2026-10-30.

## What this is
A **MATLAB biomechanics pipeline** analyzing **obstacle-crossing gait**. Hardware: **Xsens Awinda**
IMUs (12 sensors) + **Movella Dot** IMUs (foot/shank/thigh) + **OpenSim** inverse kinematics +
**WorldViz PPT** optical cameras (foot/obstacle markers). Goal: joint/segment kinematics, foot clearance,
and spatiotemporal measures during obstacle crossing, aggregated across participants.

- **Repo:** github.com/ehsansharafianm/imu-obstacle-crossing-analysis — branch **main**, commit **directly to main**.
- **Working dir:** `C:\Users\BiomechanicsLab2\Documents\obstacle-crossing-project` (code in `Analysis/`).
- **MATLAB R2023b**, Statistics & Machine Learning Toolbox available. Run scripts by name (interactive prompts).
- **OS:** Windows 11, PowerShell + Git Bash. Run scripts headless with `matlab -batch "scriptname"`.

## Design & data
- **Participants:** Tests **101–110** = **10 young adults** (Subject ID = Test #). Tests 4–32 are older method-development recordings.
- **Obstacles:** **Width** (W1=5 cm, W2=15 cm) × **Height** (H1, H2, H3) = 6 obstacles, each crossed by the
  **Leading** and **Trailing** limb. **Level_Walk** = baseline. Obstacle codes: 11,12,13,21,22,23 (Width-Height).
- **Leading and Trailing are treated as SEPARATE classes** (user decision) — compare within each, not across.

## Pipeline (run in order, per participant unless noted)
- `step01_open_sense_pipeline.m` — OpenSim OpenSense IK; prompts "apply heading de-drift + re-run IK?" (**yes**).
- `step02_plot_joint_angles.m` — joint-angle **viewer only** (doesn't affect results).
- `step03_plot_imu_and_joints_data.m` — sync Awinda+Dot, upsample 60 Hz, pull IK joints → **AllData**. IK
  prompt `[Enter]=auto`; AUTO picks raw vs de-drift **per joint**. Also a left/right **sign-check QC** (warn only).
- `step04_segmentation.m` — ZVP (zero-velocity) stride segmentation → **SegmentedParams**. Interactive ZVP editor (use saved edits).
- `step05_camera_sync_and_view.m`, `step06_segment_camera_trajectories.m` — camera sync + stride segmentation.
- `step07_segment_features_with_camera.m` — per-stride features + camera labels (terrain/role) → **SegTrajectories_WithCamera**; the **joint max/min figure**. Reads `manualJointValues.m`.
- `step08_crossing_parameters.m` — clearance, take-off/landing distances (auto obstacle height from markers).
- `step09_group_crossing_analysis.m` — **capstone**: aggregates all participants → `G` struct, `Summary.xlsx`
  (group mean±SD), **`SPSS.xlsx`** (one sheet, one row/participant), `Results.md`, figures.
- **No statistics step in MATLAB** — the user runs stats in **SPSS** externally (see `Statistical Analysis/`).

### Helper scripts
- `diag_participant.m` — `diag_participant(110)`: one-shot per-participant QC (IMU tracking errors, de-drift
  AUTO verdict per joint, sign check, non-physiological joint max/min → what to hand-calc).
- `manualJointValues.m` — hand-calculated joint max/min, **one section per participant**; read by step7 AND
  step9 (so hand values flow into the figure AND the group ROM/max/min). `[]` = keep automatic. **Only Test 108
  has entries so far** (right-leg heading drift; hip/knee/ankle re-measured by hand).
- `signNormTools.m` + `signTemplates.mat` — data-driven left/right sign normalization (hip + Dot segments).

## Key methods / decisions (important context)
- **Heading drift:** IMU heading (yaw) drifts badly (lab magnetometer unreliable); tilt is clean. OpenSim turns
  hidden heading drift into winding joints. **De-drift** = anatomical heading-lock (legs→pelvis). It **can
  backfire** → step3 **AUTO** applies de-drift per joint only where it lowers the IMU tracking error. There is
  **no angle wrapping** — issues are sign/drift, not ±180 wraps.
- **Sign normalization:** hip + Dot segments are sign-normalized. Knee flexion uses a **sign-invariant**
  `max(|y−stance|)`. Ankle dorsi/plantar are sign-normalized but **drift-inflated**.
- **Reliability:** **ROM (max−min)** and **camera clearance** are the drift-immune, headline metrics. **Dot
  segment tilts** (thigh/shank/foot) are clean. Absolute joint angles are **drift-limited**; the right ankle is
  systematically worst (hand-correct via `manualJointValues.m`).
- **Peak timing** = relative to **obstacle clearance** (foot-height apex), signed (neg = before clearing).
- **Two-level averaging:** per participant (mean over strides), then mean±SD across participants.
- **Manual joint values** are REAL hand measurements for drift-hit joints (NOT fabrication). Never invent numbers.

### Per-participant cleaning in step9 (group-only; steps 1–8 untouched)
- **Test 106:** a mid-trial **thigh-IMU disturbance** inflated hip/knee/thigh, worst on codes 11/13/23
  (W1_H1, W1_H3, W2_H3). The `CLEAN` config applies **only to 106** and **only to** `hip_flexion`,
  `knee_angle`, `Thigh`. **Current policy (2026-10-28): all conditions KEPT** — a 3×MAD stride gate + robust
  median removes the inflated strides, so 106 is no longer blank for those obstacles. (Earlier it dropped those
  3 whole conditions; that whole-condition exclusion was removed at the user's request.)
- **Test 109:** hip/knee/ankle (IK) for **W2_H1 and W2_H3** are genuinely unusable → left **blank (NaN)** in the
  sheet. Its Dot **segments**, clearance, and spatiotemporal for those conditions ARE present. Policy: keep every
  available variable; only truly-missing conditions are blank.

## step9 SPSS export — CURRENT SPEC (set by the user)
`GroupCrossing_YoungAdults_SPSS.xlsx` = **one sheet, one row per participant (n=10), 3-decimal values**, for SPSS.
Column = `class_name_condition` (e.g. `joint_hip_flexion_W2_H3_Leading`). **Within each variable, all 6 Leading
obstacle columns come first, then all 6 Trailing**, then a `Level_Walk` baseline column where it applies
(clearance has no Level_Walk; timing keeps it). Edit the `VARS` table inside `writeSpssWide()` to change the set.
**Five named classes, in this order:**
- **clearance** (cm): toe, heel, min, take-off, landing. *(T1 values are mm internally → scaled ×1/10 to cm so
  they match the figures/Summary. This was a bug fixed 2026-10-28 — don't re-introduce mm.)*
- **joint** (deg): hip_flexion (peak), hip_rom, knee_flexion (peak), knee_rom, ankle_rom.
- **segment** (deg, Dot): thigh_flexion (fwd tilt), thigh_rom, shank_backward, shank_forward, shank_rom, foot_rom.
- **timing** (% gait cycle vs clearance): hip, knee, ankle, footheight, foot, shank, thigh (all 7).
- **spatiotemporal**: stride (cm), cadence (steps/min), speed (m/s).

Internal source keys (in `VARS` as `{class,name,source-group,source-key,desc}`): peak angles → `PEX`
(`hip_pk_flex`, `knee_pk_flex`, `thigh_fwd`, `shank_back`, `shank_fwd`); ROM → `ROM` (hip_flexion/knee_angle/
ankle_angle) and `SROM` (Thigh/Shank/Foot); clearance → `T1`; timing → `PKT`; spatiotemporal → `SPT`.
`printSpssLegend()` prints a per-class legend to the command window on every run.

## Statistical analysis (external, in SPSS)
`Statistical Analysis/` holds the user's SPSS work: `dataset.sav`, `anova-analysis.spv`, `OUTPUT.pdf`, and a copy
of the SPSS input sheet. **NOTE:** that copy can lag behind the latest step9 run — after re-running step9, the
fresh sheet is `Results/Group Analysis/GroupCrossing_YoungAdults_SPSS.xlsx`; re-import it into SPSS.

## Conventions / constraints
- **Commit directly to main.** End commit messages with: `Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>`.
- **Keep `checkcode` CLEAN** on edited files. (One pre-existing STRCMP/UPPER lint in step9 ~L647 is NOT ours — ignore.)
- **GitHub rejects files >100 MB.** Before committing data, scan for oversize files. Currently **excluded** (synced
  separately, too big): `Data/Pkmas/test101/test101-E.txt` (111 MB) and `Data/Pkmas/test102/…9-59-35 AM - E.txt`
  (129 MB). Other large Pkmas `-E.txt` / `.mat` / `.wmv` (50–100 MB) are committed (GitHub warns but accepts).
- **Figures: PNG only** (no PDF). Outputs under `Results/Group Analysis/`.
- **Close Excel/SPSS before re-running step9** — it overwrites `SPSS.xlsx`/`Summary.xlsx`; an open file makes the
  run crash at `writeSpssWide` with "file might be open by another application."
- **Obsidian Vault/** holds step notes + `Session Changelog.md` (read for history).
- `.m` files were renamed step01…step09 (history preserved).

## Current state
Steps 01–09 working for **n=10 (Tests 101–110)**. `GroupCrossing_YoungAdults_SPSS.xlsx` is the tailored wide sheet
described above. Last commits on main: tailored SPSS variable set + Test 110; regenerated n=10 results.

## Likely next steps
- Add participants: run pipeline → `diag_participant(NNN)` (QC) → hand-calc flagged joints in `manualJointValues.m`
  (add a new section) → add NNN to `TESTS` in step9 → close Excel → re-run step9 → re-import sheet into SPSS.
- Keep the SPSS sheet and the `Statistical Analysis/` copy in sync after each step9 run.
- Rebuild in-MATLAB group statistics only if asked (user prefers small, incremental steps).
