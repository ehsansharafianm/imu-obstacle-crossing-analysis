# Awinda / Dot IMU Analysis Pipeline

MATLAB pipeline for processing Xsens **Awinda** and Movella **Dot** IMU data,
running OpenSim **OpenSense** inverse kinematics, comparing the two systems,
segmenting gait into strides, and analysing obstacle crossings by **side**
(Left / Right) and by **limb role** (Leading / Trailing).

Run the scripts **from the `Analysis/` folder**. Each prompts for a **Test
number** `N`. (Step 5 auto-locates the project folder, and asks for the path if
it can't find it.)

---

## Folder structure

```
Analysis Environment/                 <- project root (contains Data & Results)
├── Analysis/                         <- run all scripts from here
│   ├── step1_open_sense_pipeline.m
│   ├── step2_plot_joint_angles.m
│   ├── step3_plot_imu_and_joints_data.m
│   ├── step4_segmentation.m
│   ├── step5_plot_segmented_features.m
│   ├── step5_results_access.md       (how to read step-5 outputs)
│   ├── plot_dot_imu.m                 (Dot-only sanity plot)
│   ├── Setup/   myIMUMappings.xml (+ *_Setup.xml, GUI-only)
│   └── Model/   Rajagopal_2015.osim + Geometry/
├── Data/
│   ├── Awinda IMUs/Test N/           raw Xsens MT_*.txt (+ .mtb)
│   └── Dot IMUs/Test N/              IMU1..6_*.csv, FeatureLog_IMU1/2_*.csv,
│                                     "Logger Subject … .txt"
└── Results/
    ├── OpenSim Outputs/Test N/        OpenSense outputs (steps 1-2)
    │   ├── STOFiles/                 *_orientations.sto
    │   ├── Rajagopal_2015_calibrated.osim
    │   ├── IKResults/                ik_*.mot + *_orientationErrors.sto
    │   ├── IMU_IK_Setup.xml          IK tool setup (re-runnable)
    │   ├── Figures/                  joint-angle PNGs (step 2)
    │   └── opensim.log
    └── Parameters Output/Test N/      comparison / segmentation / features
        ├── AllData_TestN.xlsx        multi-sheet export (step 3)
        ├── AllData_TestN.mat         Data struct (step 3)
        ├── SegmentedParams_TestN.mat ZVPs + segmentation (step 4)
        ├── WindowFeatures_SideBased_TestN.xlsx   labelled windows (step 5)
        ├── SegTrajectories_SideBased_TestN.mat   trajectories + labels (step 5)
        └── *.png
```

---

## Requirements

- **OpenSim 4.x MATLAB API** on the path (`org.opensim.modeling.*`) — step 1.
- **Sensor Fusion and Tracking Toolbox** (or Navigation / Robotics System
  Toolbox) for `quaternion` / `eulerd` — step 3.
- **Signal Processing Toolbox** for `findpeaks` — step 4.

---

## Pipeline order

```
step1  ->  step2                         (OpenSim joint angles, Awinda only)
step3  ->  step4  ->  step5              (comparison -> segmentation -> features)
```
- step1 before step2, and before step3 (for joint angles in the comparison).
- step3 before step4 (step4 reads `AllData_TestN.mat`).
- step4 before step5 (step5 reads `AllData_TestN.mat` + `SegmentedParams_TestN.mat`).

---

## step1_open_sense_pipeline.m — Raw Awinda → OpenSim IK

Converts raw Awinda `.txt` (quaternion columns) to an OpenSim orientations
`.sto`, calibrates the Rajagopal model, runs IMU inverse kinematics, and prints
a per-sensor orientation-error summary.

- **Input:** `../Data/Awinda IMUs/Test N/MT_*.txt`, `Setup/myIMUMappings.xml`,
  `Model/Rajagopal_2015.osim` (+ `Geometry/`).
- **Output (`../Results/OpenSim Outputs/Test N/`):** `STOFiles/*_orientations.sto`,
  `Rajagopal_2015_calibrated.osim`, `IKResults/ik_*_orientations.mot` (+ errors),
  `IMU_IK_Setup.xml`, `opensim.log`.
- **Freed joint caps:** `freeCoords = true` (default) unclamps the lower-limb
  coordinates (`hip_*`, `knee_angle*`, `ankle_angle*`, `subtalar*`, `mtp*`) and
  widens their range to ±`freeRangeDeg` (180°) on the calibrated model, so IK is
  no longer pinned at the model's joint limits (the "flat 120°" artefact). Set
  `freeCoords = false` to restore the model's default limits.
- **Replay the "simulation":** open the calibrated `.osim` in the OpenSim GUI and
  `Load Motion` the `ik_*.mot`. (A video of the live Simbody window can't be
  exported via the API — use the GUI's capture, or the visualizer's Save Movie.)
- **Notes:** custom reader parses `Quat_q0..q3` directly. `DATA_RATE = 40` Hz.
  Runs OpenSim in a local temp folder (long Google-Drive paths break native I/O)
  then copies the results back.

## step2_plot_joint_angles.m — View IK joint angles

Interactive viewer of the IK joint angles (checkbox per coordinate, Line/Scatter,
Save PNG). **Input:** newest `IKResults/ik_*.mot`.

## step3_plot_imu_and_joints_data.m — Dot vs Awinda comparison + export

Reads both systems, converts orientation to **Euler ZXY (deg)** (`eulerd`;
Awinda uses `ZXY`, Dot `ZYX` to avoid the gimbal fold), strips the Dot terrain
packet offset (`mod 1e6`), crops Dot to the common packet window, **syncs**
Awinda to Dot on the first left-foot lift peak, **upsamples** to 60 Hz, plots
and exports.

- **Output (`../Results/Parameters Output/Test N/`):**
  - `AllData_TestN.xlsx` — sheets `Dot IMUs Foot/Thigh/Shank`,
    `Awinda IMUs Foot/Thigh/Shank`, `Awinda IMUs Pelvis and Sternum`, `Joints`
    (Packet, Euler Z/X/Y, Acc, Gyro; 4 decimals).
  - `AllData_TestN.mat` — `Data` struct (`.time, .fs, .sync, .imu(k), .joints`).
  - Figures: sync check, IMU comparison, combined (joints + IMU).
- **Conventions:** joints limited to hip/knee/ankle (no hip rotation, no knee
  beta); Right Thigh & Right Shank (Awinda) Euler angles negated for sign
  consistency.

## step4_segmentation.m — Gait events (ZVP) + stride segmentation

Detects gait events per side from that side's **Dot foot IMU**, then segments
every signal into strides — both **normalized** (0-100 %) and **time-domain**.

- **Input:** `AllData_TestN.mat`. **Output:** `SegmentedParams_TestN.mat` + figures.
- **ZVP strategy:** toe-offs = inverted minima of foot **roll = Euler X**;
  candidates = `|gyro| < OMEGA_THRESH` AND `|acc| < ACC_THRESH`; one ZVP =
  midpoint of candidates between consecutive toe-offs.
- **Segmentation:** each signal cut **mid-stance (ZVP) → next ZVP**. Left-side
  signals use the **Left** foot ZVPs, right-side the **Right** (independent of
  leading/trailing role). `ZVP_SKIP_START = 1` drops the first transitional stride.
  - **Normalized:** resampled to `NSEG = 200` points (0-100 %).
  - **Time-domain:** same cycles kept as **raw samples**, NaN-padded to the
    longest cycle; relative time (0 s at each cycle start).
- **Figures:** (1) ZVP detection; (2) stride viewer — normalized (gait %);
  (3) stride viewer — time-domain (s).
- **`SegmentedParams_TestN.mat` (`Seg`):** `zvpL`, `zvpR`, `nseg`, `pct`, `dt`,
  `timeAxis`, and `Seg.signal(k)` (`.label`, `.type`, `.side`) with
  `.strides`/`.mean`/`.sd` (normalized, `NSEG × nStrides`) and
  `.stridesTime`/`.meanTime`/`.sdTime` (time-domain, `maxLen × nStrides`).
  **All cycles of every signal are stored** (raw, per physical side, no label
  filtering), in both domains. Access, e.g.:

  ```matlab
  Seg   = load('SegmentedParams_Test11.mat').Seg;
  names = {Seg.signal.label};
  s     = Seg.signal(strcmp(names,'IMU: Left Foot (Dot) X'));
  plot(Seg.pct,      s.strides);       % all normalized cycles (NSEG × nStrides)
  plot(Seg.timeAxis, s.stridesTime);   % all time-domain cycles (raw, seconds)
  ```
  For cycles **labelled** by terrain and leading/trailing (Left & Right combined),
  use step 5's `SegTrajectories_SideBased_TestN.mat` instead (below).

## step5_plot_segmented_features.m — Obstacle features: Side & Leading/Trailing

Links the Dot **FeatureLog** windows (per foot) to the step-4 cycles, reads the
**Logger** to label each obstacle crossing's leading leg, and produces the
side-based and leading/trailing analyses.

- **Input:** `Data/Dot IMUs/Test N/` (`FeatureLog_IMU1/2_*.csv`,
  `Logger*.txt`), `AllData_TestN.mat`, `SegmentedParams_TestN.mat`.
- **What it does:**
  - Keeps labelled windows; **dedups** consecutive contiguous same-`Height*_Depth*`
    windows, keeping the larger `Max_Height_m`.
  - **Matches** each window to its step-4 cycle by searching the cycles' Dot
    packet ranges (FeatureLog and post-processed packets differ slightly —
    matched by closest packet, not assumed equal).
  - **Leading/Trailing:** from the Logger lines
    `>>> Leading leg is Right|Left|Unknown for H2_D1 crossing (Start pkt: …, End pkt: …)`,
    each obstacle cycle is tagged Leading / Trailing (the other limb) / Unknown.
  - **Unknown handling:** if the log has `Unknown` crossings, step 5 first plots
    the figures, then asks you (per crossing, with its packets and Left/Right
    cycle numbers) which limb led; it then re-plots with your answers and exports.
    No Unknowns → it just plots and exports.
- **Figures:** (1) bar plots — stride length & max height, Left/Right (top) and
  Leading/Trailing (bottom); (2) Left-vs-Right viewer (gait %); (3) Leading-vs-
  Trailing viewer (gait %); (4) Left-vs-Right viewer (time); (5) Leading-vs-
  Trailing viewer (time); (6-9) the **ZHC foot-height trajectory** in the same
  four views (Left/Right and Leading/Trailing, gait % and time); (10-11) **foot
  height vs horizontal distance** (Left/Right and Leading/Trailing) — the
  foot-clearance-over-distance view. Figures 6-11 have a y-axis in **metres** and
  a wider "compact" layout. Viewers: terrain/role colour, terrain checkboxes,
  per-group toggles (Fig 3/5/7/9/11: Leading/Trailing/Unknown + a **Level Walk**
  toggle), Mean ± SD, Show cycle numbers, Save PNG. Figures 2/3/6/7 are 0-100 %
  gait cycle; 4/5/8/9 are raw **time** (s); 10/11 are height vs **distance** (m).
  Figures 6-11 only appear if step 4 produced trajectories (step 3 saved the quaternion).
- **Output (`../Results/Parameters Output/Test N/`):**
  - `WindowFeatures_SideBased_TestN.xlsx` — sheets `Left and Right`,
    `Leading vs Trailing` (paired per crossing, with packets/cycle/height/stride),
    and `Level Walk`.
  - `SegTrajectories_SideBased_TestN.mat` — `S5` struct: per-signal trajectory
    matrices — **`.Y`** (normalized, `S5.pct`) and **`.Yt`** (time-domain,
    `S5.time`) — plus per-cycle `side` / `terrain` / `role` / `cycle`, `Feat` and
    the parsed `log`. When step 4 produced ZHC trajectories, `S5.zhc` holds the
    **foot-height/position trajectories** per cycle, tagged the same way (see
    **Accessing step-5 results** and **ZHC foot trajectories** below).

### Accessing step-5 results

**Excel — `WindowFeatures_SideBased_TestN.xlsx`**

- `Left and Right` — one row per crossing, the Left & Right windows side by side
  (`Left_Role`/`Right_Role`, `*_StartPkt`, `*_EndPkt`, `*_Cycle`, `*_Height_m`,
  `*_Stride_m`).
- `Leading vs Trailing` — one row per crossing, leading vs trailing limb side by
  side (`Leading_Side`, `Leading_StartPkt/EndPkt/Cycle/Height_m/Stride_m` and the
  matching `Trailing_*`).
- `Level Walk` — every level-walk window (`Side`, packets, `Cycle`, height, stride).

`Win_*Pkt` = FeatureLog (real-time) packets; `Cyc_*Pkt` = the matched step-4
cycle's Dot packets; `Cycle` = the cycle index used everywhere below.

**MATLAB — `SegTrajectories_SideBased_TestN.mat`** (`S5` struct)

| Field | Meaning |
|-------|---------|
| `S5.test` | test number |
| `S5.pct` | `NSEG×1` gait-cycle axis, 0–100 % (x-axis for `.Y`) |
| `S5.time` | `maxLen×1` time axis in seconds (x-axis for `.Yt`) |
| `S5.terrains` | canonical terrain order |
| `S5.signal` | struct array, one entry per sensor/joint (Left & Right cycles combined) |
| `S5.Feat` | per-window features (terrain, start/end packet, height, stride) per foot |
| `S5.log` | leading-leg crossings from the Logger (`terr`, `lead` `'L'/'R'/'U'`, `s`, `e`) |

Each `S5.signal(k)`: `.name` (e.g. `'IMU: Foot (Dot) X'`, `'Joint: knee_angle'`),
`.Y` (`NSEG × Ncyc`, **normalized** trajectory, one column per cycle), `.Yt`
(`maxLen × Ncyc`, **time-domain** trajectory, NaN-padded), `.side` (`'L'`/`'R'`),
`.terrain` (`'Height1_Depth1'` … / `'Level_Walk'` / `''`), `.role`
(`'Leading'`/`'Trailing'`/`'Unknown'`/`''`), `.cycle` (per-side cycle index =
the Excel `Cycle`). The columns of `.Y` and `.Yt` line up (same cycles).

Trajectories are the signals the viewers plot: each IMU's Euler **X** (deg) and
the hip/knee/ankle joint angles (deg). Use `.Y` with `S5.pct` for gait-% curves,
`.Yt` with `S5.time` for time-domain. `.cycle` cross-references columns to the
Excel sheets and the "Show cycle numbers" labels.

```matlab
S     = load('SegTrajectories_SideBased_Test11.mat').S5;
names = {S.signal.name};
sig   = S.signal(strcmp(names, 'IMU: Foot (Dot) X'));

% leading- vs trailing-limb cycles on Height1_Depth1  (NSEG × n matrices)
lead  = sig.Y(:, strcmp(sig.terrain,'Height1_Depth1') & strcmp(sig.role,'Leading'));
trail = sig.Y(:, strcmp(sig.terrain,'Height1_Depth1') & strcmp(sig.role,'Trailing'));
plot(S.pct, mean(lead,2,'omitnan'), S.pct, mean(trail,2,'omitnan'));

% every level-walk cycle of the knee
kn = S.signal(strcmp(names,'Joint: knee_angle'));
lw = kn.Y(:, strcmp(kn.terrain,'Level_Walk'));

% only the left foot's leading cycles
leadLeft = sig.Y(:, strcmp(sig.role,'Leading') & strcmp(sig.side,'L'));

% TIME-DOMAIN (raw, non-normalized): use .Yt with S5.time (seconds)
m      = strcmp(sig.terrain,'Height1_Depth1') & strcmp(sig.role,'Leading');
leadT  = sig.Yt(:, m);                 % maxLen × n (NaN-padded)
plot(S.time, leadT);                   % each cycle 0..its own duration
```

The ZHC foot-height trajectory is also carried as an extra signal
`S.signal(strcmp(names,'ZHC Height: Foot'))` — same `.Y/.Yt/.side/.terrain/.role/.cycle`
layout as above, but its values are **height in metres** (not degrees), so it
filters by terrain/side/role with the exact same one-liners.

### ZHC foot trajectories (`S5.zhc`)

When step 4 built trajectories (needs the quaternion saved by step 3), step 5 also
stores the full **foot-position reconstruction** per cycle, tagged like everything
else so it slices by terrain / side / leading-trailing:

| Field | Meaning |
|-------|---------|
| `S5.zhc.L`, `S5.zhc.R` | per-foot ZHC output straight from step 4 |
| `S5.zhc.L.posGait` | `NSEG × 3 × Ncyc` position **[X Y Z]** per cycle, 0–100 % gait (**Z = height**) |
| `S5.zhc.L.posTime` | `maxLen × 3 × Ncyc` position **[X Y Z]** per cycle, raw time (NaN-padded) |
| `S5.zhc.L.tCont`, `.pCont` | the **whole walk** stitched continuously — time (s) and `N×3` `[X Y Z]` path |
| `S5.zhc.L.tZvp`, `.pZvp` | ZVP (stride-boundary) times and `N×3` positions on that path |
| `S5.zhc.terrainL`, `.roleL` | `1×Ncyc` terrain / role label for each Left cycle (`terrainR`/`roleR` for Right) |
| `S5.zhc.height_gait.L/.R` | height only, `NSEG × Ncyc` (0–100 %) — the matrices the viewers plot |
| `S5.zhc.height_time.L/.R` | height only, `maxLen × Ncyc` (time); x-axis = `S5.zhc.time` |
| `S5.zhc.height_dist.L/.R` | height only, `NSEG × Ncyc` vs horizontal distance; x-axis = `S5.zhc.dist` (m) |
| `S5.zhc.all` | **combined per-cycle table (Left then Right) — the step-6 stats input** |
| &nbsp;&nbsp;`.side/.terrain/.role/.cycle` | `1×Ncyc` labels for every cycle |
| &nbsp;&nbsp;`.Hgait/.Htime/.Hdist` | height in all three domains, `samples × Ncyc`, column-aligned to the labels |
| &nbsp;&nbsp;`.peak` | `1×Ncyc` peak clearance (m) per cycle |

**Why this is useful — worked examples:**

```matlab
S = load('SegTrajectories_SideBased_Test11.mat').S5;

% 1) Mean foot-clearance profile over a given obstacle, leading limb.
%    Combine both feet's cycles, then keep the ones tagged Leading on H2_D1.
Hg   = [S.zhc.height_gait.L, S.zhc.height_gait.R];      % NSEG × allCycles
terr = [S.zhc.terrainL,      S.zhc.terrainR];
role = [S.zhc.roleL,         S.zhc.roleR];
sel  = strcmp(terr,'Height2_Depth1') & strcmp(role,'Leading');
plot(S.pct, mean(Hg(:,sel),2,'omitnan'));  xlabel('Gait %'); ylabel('Height (m)');

% 2) Peak foot clearance (max height) per cycle -> compare terrains / limbs.
peakH = max(Hg,[],1,'omitnan');            % 1 × allCycles, metres
clearLevel = peakH(strcmp(terr,'Level_Walk'));       % baseline swing clearance
clearObst  = peakH(strcmp(terr,'Height3_Depth1'));   % over the tallest obstacle

% 3) Leading vs trailing clearance on the same obstacle (time-domain height).
Ht = [S.zhc.height_time.L, S.zhc.height_time.R];
lead  = Ht(:, strcmp(terr,'Height1_Depth1') & strcmp(role,'Leading'));
trail = Ht(:, strcmp(terr,'Height1_Depth1') & strcmp(role,'Trailing'));
plot(S.zhc.time, mean(lead,2,'omitnan'), S.zhc.time, mean(trail,2,'omitnan'));

% 4) Whole continuous path (e.g. left foot) with the ZVP boundaries marked.
plot3(S.zhc.L.pCont(:,1), S.zhc.L.pCont(:,2), S.zhc.L.pCont(:,3)); hold on;
plot3(S.zhc.L.pZvp(:,1),  S.zhc.L.pZvp(:,2),  S.zhc.L.pZvp(:,3), 'ko');

% 5) Foot clearance vs horizontal DISTANCE (leading limb, H2_D1) - the classic
%    "height per distance travelled" curve; x-axis is S5.zhc.dist in metres.
Hd  = [S.zhc.height_dist.L, S.zhc.height_dist.R];
sel = strcmp(terr,'Height2_Depth1') & strcmp(role,'Leading');
plot(S.zhc.dist, mean(Hd(:,sel),2,'omitnan'));
xlabel('Horizontal distance (m)'); ylabel('Height (m)');
```

For **step 6 statistics**, `S5.zhc.all` is the convenient one-stop table — every
cycle already labelled by side / terrain / role, with its height in all three
domains and a ready `.peak` clearance:

```matlab
A = load('SegTrajectories_SideBased_Test11.mat').S5.zhc.all;
isObs = ~strcmp(A.terrain,'Level_Walk') & ~cellfun(@isempty,A.terrain);
% peak clearance grouped by terrain x role (drop unlabelled cycles):
[g,gt,gr] = findgroups(A.terrain(isObs)', A.role(isObs)');
peakMean  = splitapply(@(v) mean(v,'omitnan'), A.peak(isObs)', g);
stats = table(gt, gr, peakMean);
```

The height trajectory answers the study's core question directly: **how high the
foot is lifted through each obstacle crossing**, per limb and per terrain. Its
peak is a foot-clearance measure; its shape vs **time/gait %** shows *when* in the
cycle the foot clears, while its shape vs **horizontal distance** (`height_dist`)
shows *where* over the ground it clears — the natural view for comparing clearance
against obstacle position. The continuous `pCont`/`pZvp` path gives step length
and the walking trace for sanity-checking the reconstruction.

---

## Tunable settings (top of each file)

- **step1:** `DATA_RATE`, visualization flags, `freeCoords`, `freeRangeDeg`.
- **step3:** `TARGET_RATE` (60), `PACKET_MODULUS` (1e6), `PEAK_MIN_DEG`, appearance.
- **step4:** `MIN_PROMINENCE`, `MIN_PEAK_DIST`, `OMEGA_THRESH`, `ACC_THRESH`,
  `ROLL_COL_*/ROLL_SIGN_*`, `NSEG`, `ZVP_SKIP_START`.
- **step5:** `LOG_PKT_TOL` (window↔log packet match), `TERRAIN_ORDER`.

## Sensor map (Awinda IDs → body)

| Body | Awinda ID | Dot |
|------|-----------|-----|
| Sternum | 00B4AB26 | - |
| Pelvis | 00B4AB22 | - |
| Left Foot | 00B4AB23 | IMU1 |
| Right Foot | 00B4AB29 | IMU2 |
| Left Thigh | 00B4AB2D | IMU3 |
| Right Thigh | 00B4AB2B | IMU4 |
| Left Shank | 00B4AB25 | IMU5 |
| Right Shank | 00B4AB27 | IMU6 |
