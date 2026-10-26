# Project Handoff — IMU Obstacle-Crossing Analysis

Paste this into a new Claude Code chat to bring it up to speed.

## What this is
A **MATLAB biomechanics pipeline** analyzing **obstacle-crossing gait**. Hardware: **Xsens Awinda**
IMUs (12 sensors) + **Movella Dot** IMUs (foot/shank/thigh) + **OpenSim** inverse kinematics +
**WorldViz PPT** optical cameras (foot/obstacle markers). Goal: joint/segment kinematics, foot clearance,
and spatiotemporal measures during obstacle crossing, aggregated across participants.

- **Repo:** github.com/ehsansharafianm/imu-obstacle-crossing-analysis — branch **main**, commit **directly to main**.
- **Working dir:** `C:\Users\BiomechanicsLab2\Documents\obstacle-crossing-project` (code in `Analysis/`).
- **MATLAB R2023b**, Statistics & Machine Learning Toolbox available. Run scripts by name (interactive prompts).

## Design & data
- **Participants:** Tests **101–109** = 9 young adults (Subject ID = Test #). Tests 4–32 are older method-development recordings.
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
- `step07_segment_features_with_camera.m` — per-stride features + camera labels (terrain/role) → **SegTrajectories_WithCamera**; the **joint max/min figure (figure 3)**. Reads `manualJointValues.m`.
- `step08_crossing_parameters.m` — clearance, take-off/landing distances (auto obstacle height from markers).
- `step09_group_crossing_analysis.m` — **capstone**: aggregates all participants → `G` struct, `Summary.xlsx`
  (group mean±SD), **`SPSS.xlsx`** (one sheet, one row/participant, all variables — for SPSS), `Results.md`, figures.
- **step10 (statistics) was removed** — being rebuilt incrementally; user runs SPSS externally for now.

### Helper scripts
- `diag_participant.m` — `diag_participant(109)`: one-shot per-participant QC (IMU tracking errors, de-drift
  AUTO verdict per joint, sign check, non-physiological joint max/min → what to hand-calc).
- `manualJointValues.m` — hand-calculated joint max/min, **one section per participant**; read by step7 AND
  step9 (so hand values flow into the figure AND the group ROM/max/min). `[]` = keep automatic.
- `signNormTools.m` + `signTemplates.mat` — data-driven left/right sign normalization (hip + Dot segments).

## Key methods / decisions (important context)
- **Heading drift:** IMU heading (yaw) drifts badly (lab magnetometer unreliable); tilt is clean. OpenSim turns
  hidden heading drift into winding joints. **De-drift** = anatomical heading-lock (legs→pelvis). It **can
  backfire** (e.g. Test 107 wound a hip to 27,544°) → step3 **AUTO** applies de-drift per joint only where it
  lowers the IMU tracking error. There is **no angle wrapping** — issues are sign/drift, not ±180 wraps.
- **Sign normalization:** hip + Dot segments are sign-normalized (left/right & per-trial sign flips). Knee flexion
  uses a **sign-invariant** `max(|y−stance|)`. Ankle dorsi/plantar are sign-normalized but **drift-inflated**.
- **Reliability:** **ROM (max−min)** and **camera clearance** are the drift-immune, headline metrics. **Dot
  segment tilts** (thigh/shank/foot) are clean. Absolute joint angles are **drift-limited** (secondary, caveated);
  the **right ankle** is systematically the worst (hand-correct via `manualJointValues.m`).
- **Peak timing** = relative to **obstacle clearance** (foot-height apex), signed (neg = before clearing).
- **Two-level averaging:** per participant (mean over strides), then mean±SD across participants.
- **Manual joint values** are REAL hand measurements for drift-hit joints (NOT fabrication); they replace the
  automatic value per participant and ROM = max−min reflects them. Keep them documented, never invent numbers.

## Conventions / constraints
- **Commit directly to main.** End commit messages with: `Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>`.
- **Keep `checkcode` CLEAN** on edited files (ignore pre-existing warnings).
- **GitHub rejects files >100 MB.** Raw data in git: Awinda `.txt` + Dot `.csv` (Tests 101–109). **Excluded**:
  `.mtb` (Xsens binaries), `.wmv` (video), the >100 MB Pkmas files — synced separately.
- **Figures: PNG only** (no PDF). Outputs under `Results/Group Analysis/`.
- **Obsidian Vault/** holds step notes + `Session Changelog.md` (read for history).
- Files close in Excel before re-running step9 (it overwrites `Summary.xlsx`/`SPSS.xlsx`).

## Current state
Steps 01–09 working for n=9. `GroupCrossing_YoungAdults_SPSS.xlsx` (one sheet, per-participant, 489 vars) is ready
for SPSS. Statistics step is intentionally removed — to be rebuilt **incrementally, starting small**, when asked.

## Likely next steps
- User runs SPSS on the wide sheet (Leading & Trailing analyzed separately).
- Rebuild group statistics incrementally (non-parametric primary at n=9; Width×Height within each limb class).
- Add participants: run pipeline → `check NNN` (QC) → hand-calc flagged joints in `manualJointValues.m` → re-run step9.
