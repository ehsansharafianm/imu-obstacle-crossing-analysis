# Build report — Crossing_Master_YoungAdults

_Generated 2026-10-30 16:50._

## 1. Row counts (expected 30 crossings + 5 level walks per participant)

| participant | crossings | level | per-code counts | include_ml | notes |
|---|---|---|---|---|---|
| 101 | 32 | 8 | 11:6 12:5 13:5 21:5 22:5 23:6 | 23 | 32 crossings; codes 11/23 ~= 5; 8 level; 3 unlabelled camera passes skipped |
| 102 | 30 | 5 | 11:5 12:5 13:5 21:5 22:5 23:5 | 34 | 2 unlabelled camera passes skipped |
| 103 | 30 | 5 | 11:5 12:5 13:5 21:5 22:5 23:5 | 33 | 4 unlabelled camera passes skipped |
| 104 | 30 | 3 | 11:5 12:5 13:5 21:5 22:5 23:5 | 29 | 3 level; 2 unlabelled camera passes skipped |
| 105 | 30 | 4 | 11:5 12:5 13:5 21:5 22:5 23:5 | 29 | 4 level; 4 unlabelled camera passes skipped |
| 106 | 30 | 3 | 11:5 12:5 13:5 21:5 22:5 23:5 | 32 | 3 level; 1 unlabelled camera passes skipped |
| 107 | 30 | 4 | 11:5 12:5 13:5 21:5 22:5 23:5 | 31 | 4 level; 2 unlabelled camera passes skipped |
| 108 | 30 | 4 | 11:5 12:5 13:5 21:5 22:5 23:5 | 30 | 4 level; 1 unlabelled camera passes skipped |
| 109 | 31 | 5 | 11:5 12:5 13:6 21:5 22:5 23:5 | 30 | 31 crossings; codes 13 ~= 5; 2 unlabelled camera passes skipped |
| 110 | 30 | 5 | 11:5 12:5 13:5 21:5 22:5 23:5 | 28 | 1 unlabelled camera passes skipped |

Level strides chosen at y = 0 that the Dot app FeatureLog also tagged Level_Walk: 101: 25%, 102: 60%, 103: 60%, 104: 100%, 105: 75%, 106: 67%, 107: 75%, 108: 100%, 109: 40%, 110: 40%.

## 2. IDs and labels

- crossing_id unique: **yes** (349 rows, 349 unique).
- label columns consistent with obstacle_code: **yes** (0 inconsistent).
- Leading/trailing source: camera crossings file (Dot Logger files of Tests 101-110 contain no "Leading leg" lines). Rows whose step-7 stride role disagrees: 23 (data_quality_flag).

## 3. Missing values

### Columns never computed

- `lead_cross_step_len` — NOT COMPUTED: a step length needs the vector between the two feet. The per-stride ZHC has no common origin, and the continuous ZHC (Seg.zhc pZvp, both feet in the Dot global frame) drifts by metres over a trial: Dot vs camera step length r ~ 0 (build_report.md, task 10). Left empty.
- `trail_cross_step_len` — NOT COMPUTED (see lead_cross_step_len).

### Missing per column (FEATURE / REFERENCE / TARGET with any gap; obstacle-only columns counted on obstacle rows)

| column | role | n missing | of |
|---|---|---|---|
| `lead_thigh_max` | FEATURE | 17 | 349 |
| `lead_thigh_min` | FEATURE | 15 | 349 |
| `lead_thigh_rom` | FEATURE | 15 | 349 |
| `lead_thigh_t_max` | FEATURE | 13 | 349 |
| `lead_thigh_t_min` | FEATURE | 13 | 349 |
| `lead_thigh_max_corr` | FEATURE | 14 | 349 |
| `lead_thigh_min_corr` | FEATURE | 16 | 349 |
| `lead_shank_max` | FEATURE | 13 | 349 |
| `lead_shank_min` | FEATURE | 13 | 349 |
| `lead_shank_rom` | FEATURE | 13 | 349 |
| `lead_shank_t_max` | FEATURE | 13 | 349 |
| `lead_shank_t_min` | FEATURE | 13 | 349 |
| `lead_shank_max_corr` | FEATURE | 13 | 349 |
| `lead_shank_min_corr` | FEATURE | 13 | 349 |
| `lead_foot_max` | FEATURE | 13 | 349 |
| `lead_foot_min` | FEATURE | 13 | 349 |
| `lead_foot_rom` | FEATURE | 13 | 349 |
| `lead_foot_t_max` | FEATURE | 13 | 349 |
| `lead_foot_t_min` | FEATURE | 13 | 349 |
| `lead_foot_max_corr` | FEATURE | 13 | 349 |
| `lead_foot_min_corr` | FEATURE | 13 | 349 |
| `trail_thigh_max` | FEATURE | 6 | 349 |
| `trail_thigh_min` | FEATURE | 8 | 349 |
| `trail_thigh_rom` | FEATURE | 7 | 349 |
| `trail_thigh_t_max` | FEATURE | 4 | 349 |
| `trail_thigh_t_min` | FEATURE | 4 | 349 |
| `trail_thigh_max_corr` | FEATURE | 8 | 349 |
| `trail_thigh_min_corr` | FEATURE | 5 | 349 |
| `trail_shank_max` | FEATURE | 4 | 349 |
| `trail_shank_min` | FEATURE | 4 | 349 |
| `trail_shank_rom` | FEATURE | 4 | 349 |
| `trail_shank_t_max` | FEATURE | 4 | 349 |
| `trail_shank_t_min` | FEATURE | 4 | 349 |
| `trail_shank_max_corr` | FEATURE | 4 | 349 |
| `trail_shank_min_corr` | FEATURE | 4 | 349 |
| `trail_foot_max` | FEATURE | 4 | 349 |
| `trail_foot_min` | FEATURE | 4 | 349 |
| `trail_foot_rom` | FEATURE | 4 | 349 |
| `trail_foot_t_max` | FEATURE | 4 | 349 |
| `trail_foot_t_min` | FEATURE | 4 | 349 |
| `trail_foot_max_corr` | FEATURE | 4 | 349 |
| `trail_foot_min_corr` | FEATURE | 4 | 349 |
| `lead_thigh_av_max` | FEATURE | 13 | 349 |
| `lead_thigh_av_min` | FEATURE | 13 | 349 |
| `lead_thigh_av_t_max` | FEATURE | 13 | 349 |
| `lead_thigh_av_t_min` | FEATURE | 13 | 349 |
| `lead_thigh_av_toeoff` | FEATURE | 13 | 349 |
| `lead_shank_av_max` | FEATURE | 13 | 349 |
| `lead_shank_av_min` | FEATURE | 13 | 349 |
| `lead_shank_av_t_max` | FEATURE | 13 | 349 |
| `lead_shank_av_t_min` | FEATURE | 13 | 349 |
| `lead_shank_av_toeoff` | FEATURE | 13 | 349 |
| `lead_foot_av_max` | FEATURE | 13 | 349 |
| `lead_foot_av_min` | FEATURE | 13 | 349 |
| `lead_foot_av_t_max` | FEATURE | 13 | 349 |
| `lead_foot_av_t_min` | FEATURE | 13 | 349 |
| `lead_foot_av_toeoff` | FEATURE | 13 | 349 |
| `trail_thigh_av_max` | FEATURE | 4 | 349 |
| `trail_thigh_av_min` | FEATURE | 4 | 349 |
| `trail_thigh_av_t_max` | FEATURE | 4 | 349 |
| `trail_thigh_av_t_min` | FEATURE | 4 | 349 |
| `trail_thigh_av_toeoff` | FEATURE | 4 | 349 |
| `trail_shank_av_max` | FEATURE | 4 | 349 |
| `trail_shank_av_min` | FEATURE | 4 | 349 |
| `trail_shank_av_t_max` | FEATURE | 4 | 349 |
| `trail_shank_av_t_min` | FEATURE | 4 | 349 |
| `trail_shank_av_toeoff` | FEATURE | 4 | 349 |
| `trail_foot_av_max` | FEATURE | 4 | 349 |
| `trail_foot_av_min` | FEATURE | 4 | 349 |
| `trail_foot_av_t_max` | FEATURE | 4 | 349 |
| `trail_foot_av_t_min` | FEATURE | 4 | 349 |
| `trail_foot_av_toeoff` | FEATURE | 4 | 349 |
| `lead_foot_acc_peak_start` | FEATURE | 13 | 349 |
| `lead_foot_acc_peak_land` | FEATURE | 13 | 349 |
| `lead_foot_acc_rms_swing` | FEATURE | 13 | 349 |
| `trail_foot_acc_peak_start` | FEATURE | 4 | 349 |
| `trail_foot_acc_peak_land` | FEATURE | 4 | 349 |
| `trail_foot_acc_rms_swing` | FEATURE | 4 | 349 |
| `stride_len_app1` | FEATURE | 12 | 349 |
| `stride_len_app2` | FEATURE | 35 | 349 |
| `speed_approach` | FEATURE | 7 | 349 |
| `speed_cross` | FEATURE | 3 | 349 |
| `cadence` | FEATURE | 3 | 349 |
| `lead_swing_time` | FEATURE | 13 | 349 |
| `trail_swing_time` | FEATURE | 4 | 349 |
| `lead_stance_time` | FEATURE | 15 | 349 |
| `trail_stance_time` | FEATURE | 6 | 349 |
| `cross_duration` | FEATURE | 16 | 349 |
| `lead_zhc_peak_toe_h` | FEATURE | 17 | 349 |
| `lead_zhc_peak_foot_h` | FEATURE | 13 | 349 |
| `lead_zhc_peak_h_t` | FEATURE | 13 | 349 |
| `lead_zhc_peak_h_x` | FEATURE | 13 | 349 |
| `lead_zhc_h_toeoff` | FEATURE | 13 | 349 |
| `lead_zhc_h_25` | FEATURE | 13 | 349 |
| `lead_zhc_h_50` | FEATURE | 13 | 349 |
| `lead_zhc_h_75` | FEATURE | 13 | 349 |
| `lead_zhc_h_cross` | REFERENCE | 3 | 349 |
| `lead_zhc_x_toeoff` | FEATURE | 13 | 349 |
| `lead_zhc_x_landing` | FEATURE | 13 | 349 |
| `lead_zhc_vz_peak` | FEATURE | 13 | 349 |
| `lead_zhc_vx_peak` | FEATURE | 13 | 349 |
| `lead_zhc_v_cross` | REFERENCE | 3 | 349 |
| `trail_zhc_peak_toe_h` | FEATURE | 7 | 349 |
| `trail_zhc_peak_foot_h` | FEATURE | 4 | 349 |
| `trail_zhc_peak_h_t` | FEATURE | 4 | 349 |
| `trail_zhc_peak_h_x` | FEATURE | 4 | 349 |
| `trail_zhc_h_toeoff` | FEATURE | 4 | 349 |
| `trail_zhc_h_25` | FEATURE | 4 | 349 |
| `trail_zhc_h_50` | FEATURE | 4 | 349 |
| `trail_zhc_h_75` | FEATURE | 4 | 349 |
| `trail_zhc_h_cross` | REFERENCE | 3 | 349 |
| `trail_zhc_x_toeoff` | FEATURE | 4 | 349 |
| `trail_zhc_x_landing` | FEATURE | 4 | 349 |
| `trail_zhc_vz_peak` | FEATURE | 4 | 349 |
| `trail_zhc_vx_peak` | FEATURE | 4 | 349 |
| `trail_zhc_v_cross` | REFERENCE | 3 | 349 |
| `lead_cam_takeoff_dist` | REFERENCE/TARGET | 1 | 303 |
| `trail_cam_takeoff_dist` | REFERENCE/TARGET | 2 | 303 |
| `lead_cam_landing_dist` | REFERENCE/TARGET | 8 | 303 |
| `trail_cam_landing_dist` | REFERENCE/TARGET | 11 | 303 |
| `lead_cam_peak_foot_h` | REFERENCE/TARGET | 3 | 349 |
| `trail_cam_peak_foot_h` | REFERENCE/TARGET | 3 | 349 |
| `lead_cam_takeoff_toeoff` | REFERENCE/TARGET | 11 | 303 |
| `trail_cam_takeoff_toeoff` | REFERENCE/TARGET | 1 | 303 |
| `role_agree` | REFERENCE | 31 | 303 |
| `imu_cross_stride_match` | REFERENCE | 31 | 303 |

### Missing FEATURE cells per participant (excluding never-computed columns)

| participant | rows | missing cells | % of feature cells |
|---|---|---|---|
| 101 | 40 | 124 | 2.8 |
| 102 | 35 | 63 | 1.6 |
| 103 | 35 | 117 | 3.0 |
| 104 | 33 | 55 | 1.5 |
| 105 | 34 | 217 | 5.7 |
| 106 | 33 | 26 | 0.7 |
| 107 | 34 | 168 | 4.4 |
| 108 | 34 | 55 | 1.4 |
| 109 | 36 | 128 | 3.2 |
| 110 | 35 | 61 | 1.6 |

## 4. Plausibility / impossible values

| check | column | range | n outside | examples |
|---|---|---|---|---|
| stance time | `trail_stance_time` | 0.2..2.5 | 1 | 109_level_p1=2.6 |
| speed | `speed_cross` | 0.2..3 | 2 | 101_level_p3=0.1, 102_level_p1=0.1 |
| cadence | `cadence` | 30..200 | 3 | 101_level_p1=23.3, 101_level_p3=7.5, 102_level_p1=20.0 |
| ZHC peak height | `lead_zhc_peak_foot_h` | 10..800 | 5 | 101_21_r1=-0.0, 103_23_r4=-31.5, 104_23_r4=-2.2 |
| clearance | `trail_cam_min_clearance` | 0..1000 | 18 | 101_23_r1=-53.6, 102_23_r3=-13.6, 102_23_r5=-19.6 |
| take-off/landing | `lead_cam_landing_dist` | -100..2000 | 1 | 104_23_r4=-114.8 |

Rows with contact_flag = 1 (min clearance <= 0): 18.

## 5. Cross-check against the SPSS sheet (per participant x condition means)

| SPSS variable | master source | n pairs | mean diff (master - SPSS) | max abs diff | worst |
|---|---|---|---|---|---|
| `clearance_min` (cm) | cam_min_clearance | 120 | -0.000 | 0.000 | 104 W1_H1 Leading |
| `clearance_takeoff` (cm) | cam_takeoff_dist | 120 | 0.000 | 0.000 | 106 W2_H3 Leading |
| `clearance_landing` (cm) | cam_landing_dist | 120 | 0.000 | 0.000 | 102 W1_H3 Trailing |
| `spatiotemporal_stride` (cm (ZHC ZVP stride)) | side:stride_mm | 120 | -0.000 | 0.000 | 110 W1_H2 Trailing |
| `spatiotemporal_cadence` (steps/min) | side:cadence | 120 | -0.000 | 0.000 | 101 W2_H1 Trailing |
| `spatiotemporal_speed` (m/s) | side:speed | 120 | -0.000 | 0.000 | 106 W2_H1 Trailing |
| `segment_thigh_rom` (deg, ZVP->ZVP stride ROM) | side:rom_thigh | 120 | 0.648 | 76.579 | 106 W1_H1 Trailing |
| `segment_shank_rom` (deg) | side:rom_shank | 120 | 0.000 | 0.000 | 106 W2_H2 Leading |
| `segment_foot_rom` (deg) | side:rom_foot | 120 | 0.000 | 0.000 | 106 W2_H1 Leading |
| `segment_thigh_rom` (deg, master = SWING ROM (expected smaller)) | thigh_rom | 120 | -30.298 | 46.424 | 106 W1_H3 Leading |
| `segment_foot_rom` (deg, master = SWING ROM (expected smaller)) | foot_rom | 120 | -0.605 | 8.887 | 101 W2_H3 Leading |

Notes: SPSS values are per-participant condition means from step 9 (Test 106 thigh = MAD-gated median, so its ROM differs). SPSS clearance/take-off/landing are cm; the master stores mm. The master's segment ROM is the SWING ROM; the ZVP-cycle ROM rows above reproduce the SPSS definition.

## 6. ZHC quality

| participant | lead h@landing mean±SD (mm) | trail h@landing | drift flags | lead Dot-cam peak-h err mean±SD (mm) | trail | lead place err mean±SD (mm) | trail |
|---|---|---|---|---|---|---|---|
| 101 | 176.7 ± 117.9 | 92.4 ± 16.7 | 13 | -7.4 ± 54.9 | 19.5 ± 91.7 | 32.4 ± 109.4 | 51.9 ± 85.6 |
| 102 | 208.5 ± 85.2 | 93.5 ± 11.5 | 1 | 17.6 ± 65.9 | 143.6 ± 147.6 | 43.9 ± 16.4 | 51.2 ± 18.9 |
| 103 | 205.4 ± 90.2 | 93.4 ± 11.4 | 1 | 7.9 ± 84.3 | 42.8 ± 80.8 | -5.3 ± 253.3 | 84.5 ± 43.1 |
| 104 | 283.8 ± 165.5 | 62.5 ± 22.5 | 3 | -13.4 ± 112.9 | 46.5 ± 38.4 | 12.3 ± 225.1 | 81.7 ± 31.1 |
| 105 | 47.5 ± 96.6 | 44.2 ± 25.7 | 1 | 8.4 ± 18.4 | 14.0 ± 70.1 | 61.3 ± 34.8 | 44.7 ± 54.7 |
| 106 | 165.0 ± 88.6 | 70.0 ± 7.1 | 0 | -22.0 ± 92.8 | -1.5 ± 89.5 | 40.8 ± 100.6 | 67.7 ± 26.1 |
| 107 | 117.7 ± 32.4 | 89.4 ± 7.9 | 0 | 51.5 ± 48.5 | -31.3 ± 77.8 | 68.6 ± 26.7 | 81.4 ± 28.8 |
| 108 | 221.1 ± 104.0 | 68.7 ± 11.8 | 3 | -68.2 ± 85.3 | 22.4 ± 75.7 | 29.3 ± 31.5 | 73.8 ± 36.4 |
| 109 | 137.4 ± 36.7 | 89.1 ± 7.1 | 1 | 26.9 ± 50.5 | 114.5 ± 86.3 | 12.5 ± 59.4 | 58.9 ± 25.1 |
| 110 | 182.3 ± 57.5 | 86.3 ± 14.4 | 6 | -7.5 ± 39.0 | -9.0 ± 124.7 | 15.3 ± 20.9 | 33.7 ± 51.0 |
| **all** | 175.9 ± 110.9 | 79.3 ± 21.6 | 29 | -1.2 ± 75.8 | 36.6 ± 105.4 | 31.1 ± 120.4 | 63.1 ± 46.5 |

Uncorrected ZHC landing drift (end-ZVP height before the level-ground correction), |mm|: median 67.7, 95th pct 240.4; drift-flag threshold = 271.4 mm (median + 3 x 1.4826 x MAD). Per participant median |drift| (lead / trail): 101 90/119, 102 34/73, 103 61/91, 104 55/131, 105 79/45, 106 93/132, 107 31/62, 108 69/28, 109 38/44, 110 42/75.

Foot sign check (median per participant of corr(Dot foot tilt, camera foot pitch) over the swing; + = Dot max is toe-up):

| participant | lead r | trail r | sign flips applied (L/R thigh, shank, foot) |
|---|---|---|---|
| 101 | 0.99 | 0.99 | L 1 1 1 / R 1 1 1 |
| 102 | 0.96 | 0.99 | L 1 1 1 / R 1 1 1 |
| 103 | 0.99 | 0.95 | L 1 1 1 / R 1 1 1 |
| 104 | 1.00 | 1.00 | L 1 1 1 / R 1 1 1 |
| 105 | 0.98 | 0.98 | L 1 1 1 / R 1 1 1 |
| 106 | 0.98 | 0.95 | L 1 1 1 / R 1 1 1 |
| 107 | 0.99 | 0.95 | L 1 1 1 / R 1 1 1 |
| 108 | 0.91 | 0.98 | L 1 1 1 / R 1 1 1 |
| 109 | 0.99 | 0.99 | L 1 1 1 / R 1 1 1 |
| 110 | 0.99 | 0.98 | L 1 1 1 / R 1 1 1 |

## 7. n per variable and Test 106 cleaning

| column | role | n (all rows) | n (include_ml) |
|---|---|---|---|
| `lead_crossing_t_cam` | REFERENCE | 349 | 299 |
| `trail_crossing_t_cam` | REFERENCE | 349 | 299 |
| `lead_thigh_max` | FEATURE | 332 | 295 |
| `lead_thigh_min` | FEATURE | 334 | 297 |
| `lead_thigh_rom` | FEATURE | 334 | 297 |
| `lead_thigh_t_max` | FEATURE | 336 | 299 |
| `lead_thigh_t_min` | FEATURE | 336 | 299 |
| `lead_thigh_max_corr` | FEATURE | 335 | 298 |
| `lead_thigh_min_corr` | FEATURE | 333 | 296 |
| `lead_shank_max` | FEATURE | 336 | 299 |
| `lead_shank_min` | FEATURE | 336 | 299 |
| `lead_shank_rom` | FEATURE | 336 | 299 |
| `lead_shank_t_max` | FEATURE | 336 | 299 |
| `lead_shank_t_min` | FEATURE | 336 | 299 |
| `lead_shank_max_corr` | FEATURE | 336 | 299 |
| `lead_shank_min_corr` | FEATURE | 336 | 299 |
| `lead_foot_max` | FEATURE | 336 | 299 |
| `lead_foot_min` | FEATURE | 336 | 299 |
| `lead_foot_rom` | FEATURE | 336 | 299 |
| `lead_foot_t_max` | FEATURE | 336 | 299 |
| `lead_foot_t_min` | FEATURE | 336 | 299 |
| `lead_foot_max_corr` | FEATURE | 336 | 299 |
| `lead_foot_min_corr` | FEATURE | 336 | 299 |
| `trail_thigh_max` | FEATURE | 343 | 297 |
| `trail_thigh_min` | FEATURE | 341 | 295 |
| `trail_thigh_rom` | FEATURE | 342 | 296 |
| `trail_thigh_t_max` | FEATURE | 345 | 299 |
| `trail_thigh_t_min` | FEATURE | 345 | 299 |
| `trail_thigh_max_corr` | FEATURE | 341 | 295 |
| `trail_thigh_min_corr` | FEATURE | 344 | 298 |
| `trail_shank_max` | FEATURE | 345 | 299 |
| `trail_shank_min` | FEATURE | 345 | 299 |
| `trail_shank_rom` | FEATURE | 345 | 299 |
| `trail_shank_t_max` | FEATURE | 345 | 299 |
| `trail_shank_t_min` | FEATURE | 345 | 299 |
| `trail_shank_max_corr` | FEATURE | 345 | 299 |
| `trail_shank_min_corr` | FEATURE | 345 | 299 |
| `trail_foot_max` | FEATURE | 345 | 299 |
| `trail_foot_min` | FEATURE | 345 | 299 |
| `trail_foot_rom` | FEATURE | 345 | 299 |
| `trail_foot_t_max` | FEATURE | 345 | 299 |
| `trail_foot_t_min` | FEATURE | 345 | 299 |
| `trail_foot_max_corr` | FEATURE | 345 | 299 |
| `trail_foot_min_corr` | FEATURE | 345 | 299 |
| `lead_thigh_av_max` | FEATURE | 336 | 299 |
| `lead_thigh_av_min` | FEATURE | 336 | 299 |
| `lead_thigh_av_t_max` | FEATURE | 336 | 299 |
| `lead_thigh_av_t_min` | FEATURE | 336 | 299 |
| `lead_thigh_av_toeoff` | FEATURE | 336 | 299 |
| `lead_shank_av_max` | FEATURE | 336 | 299 |
| `lead_shank_av_min` | FEATURE | 336 | 299 |
| `lead_shank_av_t_max` | FEATURE | 336 | 299 |
| `lead_shank_av_t_min` | FEATURE | 336 | 299 |
| `lead_shank_av_toeoff` | FEATURE | 336 | 299 |
| `lead_foot_av_max` | FEATURE | 336 | 299 |
| `lead_foot_av_min` | FEATURE | 336 | 299 |
| `lead_foot_av_t_max` | FEATURE | 336 | 299 |
| `lead_foot_av_t_min` | FEATURE | 336 | 299 |
| `lead_foot_av_toeoff` | FEATURE | 336 | 299 |
| `trail_thigh_av_max` | FEATURE | 345 | 299 |
| `trail_thigh_av_min` | FEATURE | 345 | 299 |
| `trail_thigh_av_t_max` | FEATURE | 345 | 299 |
| `trail_thigh_av_t_min` | FEATURE | 345 | 299 |
| `trail_thigh_av_toeoff` | FEATURE | 345 | 299 |
| `trail_shank_av_max` | FEATURE | 345 | 299 |
| `trail_shank_av_min` | FEATURE | 345 | 299 |
| `trail_shank_av_t_max` | FEATURE | 345 | 299 |
| `trail_shank_av_t_min` | FEATURE | 345 | 299 |
| `trail_shank_av_toeoff` | FEATURE | 345 | 299 |
| `trail_foot_av_max` | FEATURE | 345 | 299 |
| `trail_foot_av_min` | FEATURE | 345 | 299 |
| `trail_foot_av_t_max` | FEATURE | 345 | 299 |
| `trail_foot_av_t_min` | FEATURE | 345 | 299 |
| `trail_foot_av_toeoff` | FEATURE | 345 | 299 |
| `lead_foot_acc_peak_start` | FEATURE | 336 | 299 |
| `lead_foot_acc_peak_land` | FEATURE | 336 | 299 |
| `lead_foot_acc_rms_swing` | FEATURE | 336 | 299 |
| `trail_foot_acc_peak_start` | FEATURE | 345 | 299 |
| `trail_foot_acc_peak_land` | FEATURE | 345 | 299 |
| `trail_foot_acc_rms_swing` | FEATURE | 345 | 299 |
| `stride_len_app1` | FEATURE | 337 | 295 |
| `stride_len_app2` | FEATURE | 314 | 278 |
| `speed_approach` | FEATURE | 342 | 298 |
| `speed_cross` | FEATURE | 346 | 299 |
| `cadence` | FEATURE | 346 | 299 |
| `lead_swing_time` | FEATURE | 336 | 299 |
| `trail_swing_time` | FEATURE | 345 | 299 |
| `lead_stance_time` | FEATURE | 334 | 299 |
| `trail_stance_time` | FEATURE | 343 | 299 |
| `cross_duration` | FEATURE | 333 | 299 |
| `lead_zhc_peak_toe_h` | FEATURE | 332 | 298 |
| `lead_zhc_peak_foot_h` | FEATURE | 336 | 299 |
| `lead_zhc_peak_h_t` | FEATURE | 336 | 299 |
| `lead_zhc_peak_h_x` | FEATURE | 336 | 299 |
| `lead_zhc_h_toeoff` | FEATURE | 336 | 299 |
| `lead_zhc_h_25` | FEATURE | 336 | 299 |
| `lead_zhc_h_50` | FEATURE | 336 | 299 |
| `lead_zhc_h_75` | FEATURE | 336 | 299 |
| `lead_zhc_h_cross` | REFERENCE | 346 | 299 |
| `lead_zhc_x_toeoff` | FEATURE | 336 | 299 |
| `lead_zhc_x_landing` | FEATURE | 336 | 299 |
| `lead_zhc_vz_peak` | FEATURE | 336 | 299 |
| `lead_zhc_vx_peak` | FEATURE | 336 | 299 |
| `lead_zhc_v_cross` | REFERENCE | 346 | 299 |
| `trail_zhc_peak_toe_h` | FEATURE | 342 | 298 |
| `trail_zhc_peak_foot_h` | FEATURE | 345 | 299 |
| `trail_zhc_peak_h_t` | FEATURE | 345 | 299 |
| `trail_zhc_peak_h_x` | FEATURE | 345 | 299 |
| `trail_zhc_h_toeoff` | FEATURE | 345 | 299 |
| `trail_zhc_h_25` | FEATURE | 345 | 299 |
| `trail_zhc_h_50` | FEATURE | 345 | 299 |
| `trail_zhc_h_75` | FEATURE | 345 | 299 |
| `trail_zhc_h_cross` | REFERENCE | 346 | 299 |
| `trail_zhc_x_toeoff` | FEATURE | 345 | 299 |
| `trail_zhc_x_landing` | FEATURE | 345 | 299 |
| `trail_zhc_vz_peak` | FEATURE | 345 | 299 |
| `trail_zhc_vx_peak` | FEATURE | 345 | 299 |
| `trail_zhc_v_cross` | REFERENCE | 346 | 299 |
| `lead_cam_min_clearance` | REFERENCE/TARGET | 303 | 260 |
| `trail_cam_min_clearance` | REFERENCE/TARGET | 303 | 260 |
| `lead_cam_takeoff_dist` | REFERENCE/TARGET | 302 | 260 |
| `trail_cam_takeoff_dist` | REFERENCE/TARGET | 301 | 259 |
| `lead_cam_landing_dist` | REFERENCE/TARGET | 295 | 260 |
| `trail_cam_landing_dist` | REFERENCE/TARGET | 292 | 258 |
| `lead_cam_peak_foot_h` | REFERENCE/TARGET | 346 | 299 |
| `trail_cam_peak_foot_h` | REFERENCE/TARGET | 346 | 299 |
| `cam_obstacle_h` | REFERENCE/TARGET | 303 | 260 |
| `cam_obstacle_x` | REFERENCE/TARGET | 303 | 260 |
| `lead_cam_takeoff_toeoff` | REFERENCE/TARGET | 292 | 260 |
| `trail_cam_takeoff_toeoff` | REFERENCE/TARGET | 302 | 260 |
| `role_agree` | REFERENCE | 272 | 254 |
| `imu_cross_stride_match` | REFERENCE | 272 | 254 |

Test 106 MAD gate: 26 values set to NaN.

| column | code | n removed | 106 mean raw | 106 mean cleaned |
|---|---|---|---|---|
| `lead_thigh_max_corr` | 23 | 1 | 80.5 | 80.8 |
| `lead_thigh_max` | 11 | 2 | 49.7 | 54.7 |
| `lead_thigh_max` | 23 | 2 | 87.2 | 85.3 |
| `lead_thigh_min_corr` | 11 | 2 | -2.2 | 1.3 |
| `lead_thigh_min_corr` | 12 | 1 | 28.3 | 23.2 |
| `lead_thigh_min` | 11 | 1 | 2.4 | 14.7 |
| `lead_thigh_min` | 12 | 1 | 28.7 | 25.6 |
| `lead_thigh_rom` | 11 | 1 | 47.3 | 41.7 |
| `lead_thigh_rom` | 22 | 1 | 65.0 | 67.0 |
| `trail_thigh_max_corr` | 12 | 1 | 44.3 | 45.0 |
| `trail_thigh_max_corr` | 22 | 1 | 45.6 | 46.8 |
| `trail_thigh_max_corr` | 23 | 2 | 30.2 | 31.4 |
| `trail_thigh_max` | 11 | 1 | 32.9 | 36.6 |
| `trail_thigh_max` | 22 | 1 | 48.1 | 49.2 |
| `trail_thigh_min_corr` | 11 | 1 | -12.4 | -0.5 |
| `trail_thigh_min` | 11 | 1 | -7.9 | 9.2 |
| `trail_thigh_min` | 12 | 1 | 20.4 | 19.7 |
| `trail_thigh_min` | 13 | 2 | 26.1 | 26.0 |
| `trail_thigh_rom` | 11 | 1 | 40.7 | 27.4 |
| `trail_thigh_rom` | 22 | 2 | 27.5 | 28.6 |

---

# v2 review follow-up (tasks 1-13)

All tables: n = rows used; "all rows" = every row of the dataset (349 rows, 303 obstacle, 46 level), "include_ml" = 299 rows.

## Task 1. Obstacle height audit

Per participant x height class (obstacle rows, all rows). nominal = 10/20/30% of the leg length (only where a leg length is known); used = `height_cm` (step 8); marker = median per-crossing `cam_obstacle_h` (obstacle-marker centre - 20 mm); raw marker centre = marker + 2.0 cm. All cm.

| participant | class | n | nominal | used (height_cm) | marker-based | raw marker centre | used - marker | nominal - used |
|---|---|---|---|---|---|---|---|---|
| 101 | H1 | 11 | 9.0 | 9.0 | 10.7 | 12.7 | -1.7 | +0.0 |
| 101 | H2 | 10 | 18.0 | 18.0 | 19.5 | 21.5 | -1.5 | +0.0 |
| 101 | H3 | 11 | 27.0 | 27.0 | 28.6 | 30.6 | -1.6 | +0.0 |
| 102 | H1 | 10 | 9.9 | 9.9 | 11.7 | 13.7 | -1.8 | +0.0 |
| 102 | H2 | 10 | 19.8 | 19.8 | 21.8 | 23.8 | -2.0 | +0.0 |
| 102 | H3 | 10 | 29.7 | 29.7 | 31.7 | 33.7 | -2.0 | +0.0 |
| 103 | H1 | 10 | 9.4 | 10.2 | 10.8 | 12.8 | -0.6 | -0.8 |
| 103 | H2 | 10 | 18.8 | 19.7 | 20.4 | 22.4 | -0.6 | -0.9 |
| 103 | H3 | 10 | 28.2 | 29.4 | 29.9 | 31.9 | -0.5 | -1.2 |
| 104 | H1 | 10 | 8.7 | 11.2 | 11.4 | 13.4 | -0.2 | -2.5 |
| 104 | H2 | 10 | 17.3 | 19.6 | 19.8 | 21.8 | -0.1 | -2.3 |
| 104 | H3 | 10 | 25.9 | 28.5 | 28.5 | 30.5 | -0.0 | -2.5 |
| 105 | H1 | 10 | 8.8 | 6.8 | 6.8 | 8.8 | +0.0 | +2.0 |
| 105 | H2 | 10 | 17.5 | 15.4 | 15.4 | 17.4 | +0.0 | +2.1 |
| 105 | H3 | 10 | 26.2 | 24.1 | 24.1 | 26.1 | +0.0 | +2.1 |
| 106 | H1 | 10 | 10.6 | 8.9 | 9.0 | 11.0 | -0.1 | +1.7 |
| 106 | H2 | 10 | 21.2 | 19.0 | 19.1 | 21.1 | -0.0 | +2.2 |
| 106 | H3 | 10 | 31.8 | 29.1 | 29.2 | 31.2 | -0.1 | +2.7 |
| 107 | H1 | 10 | 9.6 | 7.2 | 7.3 | 9.3 | -0.1 | +2.3 |
| 107 | H2 | 10 | 19.1 | 16.7 | 16.7 | 18.7 | -0.0 | +2.4 |
| 107 | H3 | 10 | 28.6 | 26.2 | 26.4 | 28.4 | -0.2 | +2.5 |
| 108 | H1 | 10 | 9.2 | 7.2 | 7.2 | 9.2 | -0.0 | +2.0 |
| 108 | H2 | 10 | 18.3 | 16.4 | 16.4 | 18.4 | +0.0 | +1.9 |
| 108 | H3 | 10 | 27.4 | 25.5 | 25.6 | 27.6 | -0.1 | +2.0 |
| 109 | H1 | 10 | 9.3 | 7.3 | 7.5 | 9.5 | -0.1 | +2.0 |
| 109 | H2 | 10 | 18.7 | 16.6 | 16.7 | 18.7 | -0.1 | +2.1 |
| 109 | H3 | 11 | 28.1 | 26.2 | 26.2 | 28.2 | -0.0 | +1.9 |
| 110 | H1 | 10 | 8.3 | 5.4 | 5.4 | 7.4 | +0.0 | +2.9 |
| 110 | H2 | 10 | 16.6 | 14.0 | 13.9 | 15.9 | +0.1 | +2.6 |
| 110 | H3 | 10 | 24.9 | 24.0 | 24.1 | 26.1 | -0.0 | +0.9 |

Level spacing from the marker-based heights (cm). With the bar at k x 10% of the leg length, H2-H1 = H3-H2 = 10% LL and H1 = one spacing. "implied LL" = mean spacing / 0.10 is an INFERENCE, not written to `leg_length_cm`. "offset" = H1 - mean spacing (0 for a proportional set-up).

| participant | step-8 source | H2-H1 | H3-H2 | implied LL | measured LL | offset (marker - 20 mm) | offset (raw marker centre) | raw marker - nominal (H1/H2/H3) | H3/H1 (used) |
|---|---|---|---|---|---|---|---|---|---|
| 101 | typed leg length | 8.8 | 9.0 | 89 | 90.0 | +1.8 | +3.8 | +3.7 / +3.5 / +3.6 | 3.00 |
| 102 | typed leg length | 10.1 | 9.9 | 100 | 99.0 | +1.7 | +3.7 | +3.8 / +4.0 / +4.0 | 3.00 |
| 103 | auto markers | 9.5 | 9.6 | 96 | 94.0 | +1.3 | +3.3 | +3.4 / +3.6 / +3.7 | 2.88 |
| 104 | auto markers | 8.4 | 8.8 | 86 | 86.5 | +2.8 | +4.8 | +4.7 / +4.5 / +4.6 | 2.55 |
| 105 | auto markers | 8.6 | 8.7 | 87 | 87.5 | -1.9 | +0.1 | +0.0 / -0.1 / -0.1 | 3.56 |
| 106 | auto markers | 10.1 | 10.1 | 101 | 106.0 | -1.1 | +0.9 | +0.4 / -0.1 / -0.6 | 3.27 |
| 107 | auto markers | 9.3 | 9.7 | 95 | 95.5 | -2.2 | -0.2 | -0.2 / -0.4 / -0.2 | 3.62 |
| 108 | auto markers | 9.1 | 9.2 | 92 | 91.5 | -2.0 | +0.0 | +0.1 / +0.1 / +0.1 | 3.54 |
| 109 | auto markers | 9.2 | 9.5 | 94 | 93.5 | -1.9 | +0.1 | +0.1 / -0.0 / +0.1 | 3.57 |
| 110 | auto markers | 8.6 | 10.1 | 93 | 83.0 | -4.0 | -2.0 | -0.9 / -0.7 / +1.2 | 4.47 |

**Finding.** The spacing between levels is close to 10% of a plausible leg length for everyone, but the H1 offset jumps between Tests 104 and 105: median offset +1.8 cm for 101-104 vs -1.9 cm for 105-110 with the 20 mm radius subtracted (+3.8 vs +0.1 cm for the raw marker centre). The camera floor did not move (stance toe-marker z 54.5 mm in 104 vs 56.9 mm in 105, separate check), and the two obstacle markers stay at the bar ends (x = -370 / +370 mm) in every test, so it is not a camera-calibration or marker-identity change. **Most likely cause:** the bar was set proportionally (k x 10% LL) in every session, but the marker mount changed between 104 and 105. In 101-104 the marker centre sits ~3.5-4 cm above the bar top (101-102: raw marker centre 3.5 to 4.0 cm above the typed leg-length heights), so subtracting 2 cm over-estimates 103-104 by ~1.5-3 cm; in 105-110 the raw marker centre is AT a proportional height (offset ~0), so subtracting 2 cm UNDER-estimates 105-110 by ~2 cm, which is why their H1 looks low and H3/H1 is 3.5-4.5. The measured leg lengths (lab sheet, hip to ankle) confirm this: raw marker centre - 10/20/30% of the measured leg length is +3.4 to +4.7 cm in 101-104 and within +/-0.6 cm in 105-109, so the bars were set proportionally and only the marker-to-top offset changed (~3.7 cm before 105, ~0 cm from 105). Test 110 is the exception: its spacing implies a 93 cm leg vs 83 cm measured (H1/H2 ~0.8 cm below and H3 ~1.2 cm above nominal). Consequence: `height_cm` (marker - 2 cm) is ~1.5-2.5 cm too high for 103-104 and ~2 cm too low for 105-109, and the clearances shift by the same amount (the "proportional" column in task 6 shows the effect). Test 110 has unequal spacing (8.6 / 10.1 cm). `height_cm` was NOT changed. Please confirm the bar heights (tape measure / lab notes) for at least one session before and after 105.

## Task 2. Participant metadata

Filled in `Analysis/ML/participants_meta.csv` from the lab measurement sheet "Data Recording Measurements" (Google Sheet): age, body height, mass (lb x 0.45359237 -> kg), dominant leg, and `leg_length_cm` = "Hip to ankle" (it equals the leg lengths typed into step 8 for 101 = 90 cm and 102 = 99 cm). Segment and foot lengths are kept in the meta file for reference (not dataset columns). `sex` also comes from the sheet (6 F, 4 M; the PKMAS headers had listed only 101 as female).

Cells still empty:

| participant | empty cells |
|---|---|
| 101 | order_randomized |
| 102 | order_randomized |
| 103 | order_randomized |
| 104 | order_randomized |
| 105 | order_randomized |
| 106 | order_randomized |
| 107 | order_randomized |
| 108 | order_randomized |
| 109 | order_randomized |
| 110 | order_randomized |

`order_randomized` is left for you: obstacles were run in blocks (task 9), with a block order that differs between participants.

## Task 3. Toe height from the ZHC (rigid-body sensor -> toe marker)

Model per swing sample: toe rise = sensor rise + rx sin(theta) + rz (cos(theta) - 1), theta = Dot foot tilt minus its begin-ZVP value (toe-up +). The foot length and sensor position are not stored, so [rx rz] (sensor -> toe marker, foot frame, mm) is fitted by least squares to the camera toe-marker rise (swing samples of include_biomech rows, one 3-SD trim). The column uses the leave-one-participant-out (LOPO) vector, fitted on the other participants, so it uses no camera data of the participant itself. With foot length and sensor position the vector could be measured instead.

| participant | n samples | rx own | rz own | RMSE own | rx LOPO | rz LOPO | lead sensor err | lead toe err | trail sensor err | trail toe err |
|---|---|---|---|---|---|---|---|---|---|---|
| 101 | 1395 | 38 | 10 | 41 | 17 | 40 | -7.4 ± 54.9 | -7.6 ± 53.3 | 19.5 ± 91.7 | -30.9 ± 82.4 |
| 102 | 1851 | 146 | 40 | 65 | 3 | 44 | 17.6 ± 65.9 | 16.0 ± 66.2 | 143.6 ± 147.6 | 111.4 ± 141.5 |
| 103 | 1964 | -36 | 94 | 73 | 26 | 29 | 7.9 ± 84.3 | 7.3 ± 84.1 | 42.8 ± 80.8 | -7.1 ± 74.8 |
| 104 | 1606 | 39 | 24 | 27 | 16 | 37 | -13.4 ± 112.9 | -13.9 ± 112.7 | 46.5 ± 38.4 | -2.7 ± 31.0 |
| 105 | 2014 | 47 | -16 | 34 | 18 | 40 | 8.4 ± 18.4 | 3.2 ± 17.3 | 14.0 ± 70.1 | -31.3 ± 65.5 |
| 106 | 1895 | -45 | 83 | 67 | 26 | 33 | -22.0 ± 92.8 | -25.5 ± 92.4 | -1.5 ± 89.5 | -46.0 ± 85.2 |
| 107 | 1954 | 20 | -26 | 92 | 21 | 38 | 51.5 ± 48.5 | 43.0 ± 49.2 | -31.3 ± 77.8 | -72.9 ± 76.4 |
| 108 | 1980 | -64 | 66 | 88 | 22 | 40 | -68.2 ± 85.3 | -68.9 ± 86.4 | 22.4 ± 75.7 | -35.9 ± 72.4 |
| 109 | 1662 | 39 | 88 | 59 | 15 | 31 | 26.9 ± 50.5 | 22.6 ± 48.9 | 114.5 ± 86.3 | 77.4 ± 78.7 |
| 110 | 1605 | -20 | 22 | 69 | 24 | 35 | -7.5 ± 39.0 | -5.8 ± 39.2 | -9.0 ± 124.7 | -47.4 ± 112.7 |
| **all** | | | | | | | -1.2 ± 75.8 | -3.4 ± 75.1 | 36.6 ± 105.4 | -8.1 ± 102.0 |

Errors = Dot - camera peak rise, mean ± SD (mm), all rows with both values.

**Assessment.** The vector is poorly identified: the per-participant fits scatter widely (rx and rz of either sign) and the pooled LOPO vector is small (rx ~15-25 mm, rz ~30-45 mm), so the toe transform mainly removes the trailing-limb bias (mean error 36.6 -> -8.1 mm) and leaves the SD almost unchanged. The large trailing errors are not a lever-arm effect: the trailing foot crosses heel-up (camera heel peak up to ~200 mm above the toe peak), so the toe marker is the lowest point of the foot and the ZHC sensor over-reads it (task 4). Treat `*_zhc_peak_toe_h` as provisional until the foot length and sensor position are measured.

## Task 4. ZHC vs camera peak height, within participant

r = Pearson correlation across the participant's rows (obstacle + level, all rows with both values); camera rise = peak toe z in the stride - toe z at begin-ZVP.

| participant | limb | n | r sensor | r toe | sensor err mean ± SD | toe err mean ± SD |
|---|---|---|---|---|---|---|
| 101 | lead | 39 | 0.91 | 0.91 | -7.4 ± 54.9 | -7.6 ± 53.3 |
| 101 | trail | 37 | 0.79 | 0.79 | 19.5 ± 91.7 | -30.9 ± 82.4 |
| 102 | lead | 34 | 0.94 | 0.94 | 17.6 ± 65.9 | 16.0 ± 66.2 |
| 102 | trail | 34 | 0.56 | 0.57 | 143.6 ± 147.6 | 111.4 ± 141.5 |
| 103 | lead | 34 | 0.80 | 0.81 | 7.9 ± 84.3 | 7.3 ± 84.1 |
| 103 | trail | 34 | 0.84 | 0.84 | 42.8 ± 80.8 | -7.1 ± 74.8 |
| 104 | lead | 32 | 0.61 | 0.62 | -13.4 ± 112.9 | -13.9 ± 112.7 |
| 104 | trail | 33 | 0.97 | 0.98 | 46.5 ± 38.4 | -2.7 ± 31.0 |
| 105 | lead | 30 | 0.99 | 0.98 | 8.4 ± 18.4 | 3.2 ± 17.3 |
| 105 | trail | 33 | 0.83 | 0.81 | 14.0 ± 70.1 | -31.3 ± 65.5 |
| 106 | lead | 33 | 0.80 | 0.80 | -22.0 ± 92.8 | -25.5 ± 92.4 |
| 106 | trail | 33 | 0.81 | 0.80 | -1.5 ± 89.5 | -46.0 ± 85.2 |
| 107 | lead | 30 | 0.94 | 0.93 | 51.5 ± 48.5 | 43.0 ± 49.2 |
| 107 | trail | 34 | 0.86 | 0.85 | -31.3 ± 77.8 | -72.9 ± 76.4 |
| 108 | lead | 33 | 0.90 | 0.90 | -68.2 ± 85.3 | -68.9 ± 86.4 |
| 108 | trail | 34 | 0.89 | 0.90 | 22.4 ± 75.7 | -35.9 ± 72.4 |
| 109 | lead | 33 | 0.91 | 0.91 | 26.9 ± 50.5 | 22.6 ± 48.9 |
| 109 | trail | 36 | 0.72 | 0.72 | 114.5 ± 86.3 | 77.4 ± 78.7 |
| 110 | lead | 34 | 0.94 | 0.93 | -7.5 ± 39.0 | -5.8 ± 39.2 |
| 110 | trail | 34 | 0.35 | 0.32 | -9.0 ± 124.7 | -47.4 ± 112.7 |

Largest sensor-height errors in the participant x limb cells with r < 0.6 (up to 5 each). gap = |IMU apex time - camera y=0 time|; drift = uncorrected landing drift; cause = first rule that applies: gap > 0.3 s -> timing; |drift| > threshold -> drift; camera heel peak > toe peak + 100 mm -> heel-up foot; camera rise < 30 mm -> camera; toe error < half the sensor error -> lever arm; else ZVP placement.

| crossing_id | limb | ZHC peak | camera rise | err | toe err | gap s | drift mm | flags | likely cause |
|---|---|---|---|---|---|---|---|---|---|
| 102_23_r5 | trail | 652 | 228 | +424 | +381 | 0.01 | -122 | dq=0 inv=0 | foot heel-up over the obstacle: camera heel peak 222 mm above the toe peak, the toe marker is the lowest point and the sensor rides high (sensor-to-toe geometry) |
| 102_23_r1 | trail | 705 | 311 | +394 | +343 | 0.01 | -118 | dq=0 inv=0 | foot heel-up over the obstacle: camera heel peak 212 mm above the toe peak, the toe marker is the lowest point and the sensor rides high (sensor-to-toe geometry) |
| 102_22_r1 | trail | 595 | 230 | +365 | +319 | 0.03 | -90 | dq=0 inv=0 | foot heel-up over the obstacle: camera heel peak 244 mm above the toe peak, the toe marker is the lowest point and the sensor rides high (sensor-to-toe geometry) |
| 102_13_r1 | trail | 639 | 285 | +354 | +315 | 0.07 | -111 | dq=0 inv=0 | foot heel-up over the obstacle: camera heel peak 181 mm above the toe peak, the toe marker is the lowest point and the sensor rides high (sensor-to-toe geometry) |
| 102_22_r5 | trail | 563 | 251 | +312 | +274 | 0.04 | -120 | dq=0 inv=0 | foot heel-up over the obstacle: camera heel peak 243 mm above the toe peak, the toe marker is the lowest point and the sensor rides high (sensor-to-toe geometry) |
| 110_13_r3 | trail | 393 | 101 | +292 | +223 | 0.07 | 509 | dq=0 inv=0 | integration drift (drift flag) |
| 110_21_r1 | trail | 87 | 316 | -229 | -222 | 0.88 | 312 | dq=1 inv=1 | IMU apex not at the camera crossing (wrong stride / ZVP placement / sync) |
| 110_23_r2 | trail | 389 | 164 | +226 | +167 | 0.05 | 96 | dq=0 inv=0 | foot heel-up over the obstacle: camera heel peak 189 mm above the toe peak, the toe marker is the lowest point and the sensor rides high (sensor-to-toe geometry) |
| 110_23_r4 | trail | 413 | 188 | +225 | +157 | 0.00 | 145 | dq=0 inv=0 | foot heel-up over the obstacle: camera heel peak 262 mm above the toe peak, the toe marker is the lowest point and the sensor rides high (sensor-to-toe geometry) |
| 110_12_r2 | trail | 76 | 293 | -217 | -210 | 0.90 | 332 | dq=1 inv=1 | IMU apex not at the camera crossing (wrong stride / ZVP placement / sync) |

Timing mismatch counts (|IMU apex - camera y=0| > 0.3 s): lead 9 of 336, trail 46 of 345 rows.

## Task 5. IMU-only role and crossing-stride detection

Rule (Dot only): a stride is a crossing candidate if its ZHC apex > 2.0 x the participant's median stride apex; consecutive L/R candidates within 1.5 s form a crossing and the earlier foot leads. Evaluation: each camera row is matched to the nearest IMU crossing (lead apex within 1.5 s of the camera lead time). Obstacle rows only (level rows have no obstacle).

| participant | obstacle rows | apex threshold mm | IMU crossings | matched rows | role agree | crossing strides match | IMU crossings without a camera row |
|---|---|---|---|---|---|---|---|
| 101 | 32 | 176 | 19 | 19 | 100% (19/19) | 100% (19/19) | 0 |
| 102 | 30 | 191 | 30 | 30 | 100% (30/30) | 100% (30/30) | 0 |
| 103 | 30 | 189 | 29 | 29 | 100% (29/29) | 100% (29/29) | 0 |
| 104 | 30 | 160 | 29 | 28 | 100% (28/28) | 100% (28/28) | 1 |
| 105 | 30 | 134 | 27 | 27 | 100% (27/27) | 100% (27/27) | 0 |
| 106 | 30 | 155 | 27 | 27 | 100% (27/27) | 100% (27/27) | 0 |
| 107 | 30 | 207 | 30 | 30 | 100% (30/30) | 100% (30/30) | 0 |
| 108 | 30 | 129 | 30 | 30 | 100% (30/30) | 100% (30/30) | 0 |
| 109 | 31 | 169 | 28 | 28 | 100% (28/28) | 100% (28/28) | 0 |
| 110 | 30 | 155 | 24 | 24 | 100% (24/24) | 100% (24/24) | 0 |
| **all** | 303 | | | 272 | 100% (272/272) | 100% (272/272) | |

Role agreement over ALL obstacle rows (unmatched counted as disagreement): 90% (272/303).

## Task 6. Contact rows (min clearance <= 0 mm)

Alternative heights: marker = this crossing's `cam_obstacle_h`; proportional = k x (mean marker spacing) per participant (a proxy for the nominal % of leg length, which is unknown for 103-110). Clearance under another height = clearance + used height - other height. mm.

| crossing_id | participant | code | side | limb | min clearance | height used | cam_obstacle_h | clearance (marker h) | clearance (proportional h) |
|---|---|---|---|---|---|---|---|---|---|
| 101_23_r1 | 101 | 23 | L | trail | -53.6 | 270 | 286 | -69.4 | -51.7 |
| 102_23_r3 | 102 | 23 | R | trail | -13.6 | 297 | 317 | -33.9 | -16.2 |
| 102_23_r5 | 102 | 23 | R | trail | -19.6 | 297 | 318 | -40.2 | -22.2 |
| 102_13_r1 | 102 | 13 | R | trail | -2.5 | 297 | 316 | -21.8 | -5.0 |
| 106_13_r1 | 106 | 13 | L | trail | -8.1 | 291 | 289 | -6.1 | -19.9 |
| 107_13_r2 | 107 | 13 | R | trail | -11.0 | 262 | 264 | -13.4 | -35.2 |
| 107_13_r4 | 107 | 13 | L | trail | -4.6 | 262 | 262 | -4.8 | -28.8 |
| 108_22_r5 | 108 | 22 | R | trail | -0.3 | 164 | 163 | 0.5 | -20.2 |
| 108_23_r2 | 108 | 23 | R | trail | -26.5 | 255 | 258 | -29.5 | -47.3 |
| 108_23_r3 | 108 | 23 | R | trail | -35.2 | 255 | 256 | -35.9 | -56.0 |
| 108_13_r2 | 108 | 13 | R | trail | -41.8 | 255 | 255 | -41.8 | -62.6 |
| 109_13_r2 | 109 | 13 | R | trail | -36.3 | 262 | 262 | -36.3 | -55.3 |
| 109_23_r3 | 109 | 23 | L | trail | -22.8 | 262 | 263 | -24.2 | -41.8 |
| 109_23_r4 | 109 | 23 | R | trail | -53.9 | 262 | 263 | -55.5 | -72.9 |
| 109_23_r5 | 109 | 23 | L | trail | -22.5 | 262 | 263 | -24.1 | -41.5 |
| 110_23_r2 | 110 | 23 | L | trail | -49.1 | 240 | 243 | -52.1 | -88.8 |
| 110_13_r3 | 110 | 13 | L | trail | -70.8 | 240 | 241 | -71.1 | -110.5 |
| 110_12_r4 | 110 | 12 | L | trail | -9.8 | 140 | 137 | -6.0 | -56.2 |

Limb crossings with clearance <= 0 (of 606 lead + trail values on obstacle rows): used height 18, per-crossing marker height 17, proportional height 26.

## Task 7. Drift flag sensitivity

Drift flag = |uncorrected landing drift| > 271.4 mm (cohort median + 3 x MAD). Rows with either limb flagged; all rows.

| participant | rows | lead flags | trail flags | rows flagged | include_ml | include_ml_noflag |
|---|---|---|---|---|---|---|
| 101 | 40 | 5 | 8 | 11 (28%) | 23 | 23 |
| 102 | 35 | 1 | 0 | 1 (3%) | 34 | 34 |
| 103 | 35 | 1 | 0 | 1 (3%) | 33 | 33 |
| 104 | 33 | 3 | 0 | 3 (9%) | 29 | 29 |
| 105 | 34 | 1 | 0 | 1 (3%) | 29 | 29 |
| 106 | 33 | 0 | 0 | 0 (0%) | 32 | 32 |
| 107 | 34 | 0 | 0 | 0 (0%) | 31 | 31 |
| 108 | 34 | 0 | 3 | 3 (9%) | 30 | 33 |
| 109 | 36 | 0 | 1 | 1 (3%) | 30 | 30 |
| 110 | 35 | 0 | 6 | 6 (17%) | 28 | 29 |
| **all** | 349 | 11 | 18 | 27 (8%) | 299 | 303 |

| height class | rows | rows flagged |
|---|---|---|
| level | 46 | 5 (11%) |
| H1 | 101 | 6 (6%) |
| H2 | 100 | 4 (4%) |
| H3 | 102 | 12 (12%) |

## Task 8. Thigh 3xMAD gate on every participant (sensitivity)

Same rule as Test 106 (per participant x code x role, >= 4 values, |x - median| > 3 x 1.4826 x MAD -> NaN) on thigh_max/min/rom/max_corr/min_corr (10 columns x ~30 obstacle rows = ~300 cells per participant). Not applied to the dataset: the values it would remove are in `exclusions_log.csv` with action "sensitivity only (not applied)".

| participant | values removed | rows touched |
|---|---|---|
| 101 | 18 | 13 |
| 102 | 34 | 15 |
| 103 | 18 | 14 |
| 104 | 28 | 17 |
| 105 | 22 | 13 |
| 106 | 26 | 13 |
| 107 | 28 | 14 |
| 108 | 17 | 11 |
| 109 | 23 | 16 |
| 110 | 24 | 16 |

Total 238 (Test 106: 26, others: 212). With only ~5 repeats per cell the MAD is small, so a 3xMAD gate removes some values in every participant by construction: outside 106 these are mostly ordinary between-repeat variation, not sensor faults. Use these log lines only as a sensitivity check.

## Task 9. Block structure

`block_id` / `block_pos` added (META, never features). Block order by trial_order (L = level passes):

| participant | obstacle blocks | block order |
|---|---|---|
| 101 | 6 | L 11 21 23 12 13 22 |
| 102 | 6 | L 21 12 11 22 23 13 |
| 103 | 6 | L 12 22 21 13 11 23 |
| 104 | 6 | L 22 13 12 23 11 21 |
| 105 | 6 | L 13 23 22 11 12 21 |
| 106 | 6 | L 23 11 13 21 22 12 |
| 107 | 6 | L 11 12 21 13 22 23 |
| 108 | 6 | L 21 22 12 23 13 11 |
| 109 | 6 | L 12 13 22 11 23 21 |
| 110 | 6 | L 22 23 13 21 11 12 |

Same block order across participants: **NO** (10 distinct orders). A participant with exactly 6 obstacle blocks ran each obstacle in one block of consecutive repeats.

## Task 10. Step length across the obstacle from the Dot

Check: lead step = lead foot at its landing ZVP - trail foot at its stance ZVP, both from the continuous ZHC (`Seg.zhc.pZvp`, Dot global frame), projected on the lead stride direction, vs the camera toe y difference at the same ZVPs. Obstacle rows.

| participant | n | Dot median mm | camera median mm | r | error median mm |
|---|---|---|---|---|---|
| 101 | 25 | 2325 | 724 | 0.21 | 1567 |
| 102 | 30 | 7993 | 923 | -0.01 | 7053 |
| 103 | 30 | 5310 | 881 | 0.01 | 4398 |
| 104 | 30 | -9934 | 670 | -0.29 | -10458 |
| 105 | 29 | 12822 | 602 | -0.03 | 12251 |
| 106 | 30 | 15523 | 811 | 0.23 | 14735 |
| 107 | 30 | -5655 | 871 | -0.18 | -6601 |
| 108 | 30 | 3939 | 724 | -0.17 | 3198 |
| 109 | 31 | 7064 | 917 | -0.12 | 6095 |
| 110 | 27 | 14122 | 764 | 0.07 | 13443 |

**Not feasible.** The continuous ZHC of each foot accumulates metres of drift over a trial (heading drift between the two sensors, nothing ties one foot to the other), so the two feet have no usable common origin; re-anchoring within a pass would need a moment with the feet at a known relative position, which the protocol does not give. `lead_cross_step_len` / `trail_cross_step_len` stay empty.

## Task 11. Level rows

| participant | level rows | toe y=0 crossings before the first obstacle (L / R) | Dot app FeatureLog Level_Walk bouts (L / R) |
|---|---|---|---|
| 101 | 8 | 10 / 8 | 2 / 1 |
| 102 | 5 | 7 / 5 | 2 / 2 |
| 103 | 5 | 7 / 5 | 1 / 1 |
| 104 | 3 | 6 / 3 | 1 / 3 |
| 105 | 4 | 4 / 5 | 2 / 1 |
| 106 | 3 | 5 / 5 | 2 / 1 |
| 107 | 4 | 7 / 5 | 1 / 1 |
| 108 | 4 | 6 / 4 | 2 / 8 |
| 109 | 5 | 8 / 5 | 3 / 4 |
| 110 | 5 | 8 / 5 | 6 / 5 |

Total 46 level rows. A level row needs BOTH feet seen crossing y = 0 in the same pass; where the camera has more single-foot crossings than rows, one foot was occluded at y = 0. The Dot app FeatureLog tags Level_Walk strides without the camera; those could become extra level rows (lead = first foot, a stride in the middle of the bout), but the "same location as the obstacle" definition would then not hold. **No rows were added.**

## Task 12. Dictionary

Added to `data_dictionary.md` (section "Study-design notes"): camera-derived roles and crossing strides (with the role_imu result), `height_cm` = measured, not nominal, blocked order, own-foot take-off. Literature-style take-off added as `lead_cam_takeoff_toeoff` / `trail_cam_takeoff_toeoff` (toe y at the limb's own toe-off). Obstacle rows:

| column | n | median mm | IQR mm |
|---|---|---|---|
| `lead_cam_takeoff_dist` | 302 | 914 | 302 |
| `lead_cam_takeoff_toeoff` | 292 | 628 | 377 |
| `trail_cam_takeoff_dist` | 301 | 192 | 107 |
| `trail_cam_takeoff_toeoff` | 302 | -96 | 187 |

## Task 13. Descriptive medians (include_ml rows only, cleaned file; no tests)

| participant | class | n | `lead_thigh_max_corr` | `lead_thigh_rom` | `trail_shank_min_corr` | `trail_shank_rom` | `lead_zhc_peak_foot_h` | `trail_zhc_peak_foot_h` | `lead_cam_min_clearance` | `trail_cam_min_clearance` | `speed_cross` |
|---|---|---|---|---|---|---|---|---|---|---|---|
| 101 | level | 5 | 22.9 | 29.1 | -40.7 | 72.0 | 86.0 | 95.7 | - | - | 1.1 |
| 101 | H1 | 6 | 51.9 | 54.3 | -73.7 | 101.3 | 230.6 | 303.8 | 136.7 | 173.7 | 1.1 |
| 101 | H2 | 7 | 64.3 | 59.0 | -87.0 | 106.7 | 335.8 | 382.4 | 123.5 | 100.9 | 1.0 |
| 101 | H3 | 5 | 74.9 | 61.3 | -93.6 | 117.6 | 430.9 | 508.0 | 116.2 | 159.2 | 0.9 |
| 102 | level | 4 | 25.9 | 31.1 | -52.4 | 81.7 | 88.6 | 86.7 | - | - | 1.3 |
| 102 | H1 | 10 | 79.1 | 68.1 | -86.7 | 108.1 | 396.8 | 405.4 | 274.5 | 195.9 | 1.3 |
| 102 | H2 | 10 | 93.3 | 81.4 | -98.5 | 120.0 | 517.9 | 506.2 | 301.8 | 115.0 | 1.3 |
| 102 | H3 | 10 | 99.4 | 93.8 | -105.9 | 128.5 | 637.1 | 608.2 | 283.3 | 69.0 | 1.2 |
| 103 | level | 4 | 29.6 | 34.0 | -56.4 | 86.3 | 91.9 | 96.2 | - | - | 1.3 |
| 103 | H1 | 10 | 73.6 | 65.8 | -90.5 | 113.5 | 336.9 | 360.2 | 227.0 | 216.8 | 1.2 |
| 103 | H2 | 10 | 83.5 | 72.2 | -100.7 | 125.4 | 407.3 | 451.0 | 191.4 | 211.2 | 1.2 |
| 103 | H3 | 9 | 91.0 | 80.7 | -111.1 | 136.4 | 496.2 | 573.6 | 181.7 | 215.7 | 1.1 |
| 104 | level | 3 | 32.6 | 20.1 | -43.5 | 74.2 | 77.5 | 78.3 | - | - | 1.1 |
| 104 | H1 | 9 | 78.5 | 57.7 | -105.5 | 129.8 | 321.6 | 430.0 | 170.3 | 272.1 | 1.1 |
| 104 | H2 | 10 | 90.2 | 68.5 | -118.7 | 130.2 | 398.7 | 536.5 | 198.6 | 317.8 | 0.8 |
| 104 | H3 | 7 | 97.6 | 81.6 | -123.5 | 135.2 | 474.9 | 594.0 | 185.2 | 267.5 | 0.9 |
| 105 | level | 4 | 25.8 | 25.7 | -48.8 | 78.7 | 71.6 | 75.9 | - | - | 0.9 |
| 105 | H1 | 9 | 53.6 | 50.2 | -75.8 | 93.7 | 182.4 | 204.3 | 148.8 | 115.5 | 0.8 |
| 105 | H2 | 8 | 67.5 | 61.0 | -92.1 | 109.3 | 303.8 | 341.4 | 148.3 | 69.1 | 0.7 |
| 105 | H3 | 8 | 77.8 | 66.0 | -103.9 | 123.8 | 355.4 | 433.1 | 118.9 | 130.0 | 0.8 |
| 106 | level | 3 | 24.6 | 22.2 | -44.1 | 68.0 | 78.2 | 74.8 | - | - | 1.2 |
| 106 | H1 | 9 | 51.4 | 46.8 | -64.8 | 89.9 | 229.2 | 247.5 | 123.8 | 111.3 | 1.2 |
| 106 | H2 | 10 | 84.0 | 65.7 | -83.3 | 102.2 | 388.5 | 387.8 | 187.0 | 135.1 | 1.0 |
| 106 | H3 | 10 | 87.7 | 67.4 | -100.6 | 123.7 | 467.9 | 539.0 | 118.1 | 117.5 | 1.0 |
| 107 | level | 4 | 24.3 | 29.6 | -48.2 | 79.8 | 95.4 | 96.1 | - | - | 1.3 |
| 107 | H1 | 10 | 62.8 | 65.2 | -72.6 | 100.3 | 301.0 | 307.1 | 172.7 | 213.1 | 1.2 |
| 107 | H2 | 10 | 76.6 | 74.8 | -86.5 | 113.9 | 407.6 | 447.8 | 143.7 | 223.5 | 1.1 |
| 107 | H3 | 7 | 82.8 | 88.1 | -90.5 | 116.4 | 512.6 | 535.4 | 96.9 | 225.1 | 1.0 |
| 108 | level | 4 | 33.6 | 24.2 | -44.7 | 70.5 | 60.5 | 63.8 | - | - | 1.0 |
| 108 | H1 | 9 | 61.8 | 45.3 | -98.2 | 122.2 | 271.7 | 407.6 | 189.8 | 280.9 | 0.9 |
| 108 | H2 | 9 | 72.1 | 41.0 | -102.7 | 132.6 | 374.0 | 517.2 | 242.1 | 192.7 | 0.7 |
| 108 | H3 | 8 | 76.8 | 47.5 | -100.2 | 130.0 | 427.5 | 509.1 | 232.8 | 9.1 | 0.8 |
| 109 | level | 4 | 26.6 | 31.9 | -47.5 | 80.3 | 81.9 | 90.7 | - | - | 1.3 |
| 109 | H1 | 8 | 58.4 | 57.7 | -79.5 | 107.1 | 198.4 | 250.1 | 149.8 | 92.6 | 1.4 |
| 109 | H2 | 8 | 73.1 | 65.6 | -97.7 | 124.2 | 308.0 | 377.6 | 134.9 | 61.2 | 1.4 |
| 109 | H3 | 10 | 80.7 | 65.1 | -110.7 | 132.7 | 404.7 | 450.4 | 130.1 | 60.2 | 1.3 |
| 110 | level | 4 | 31.2 | 26.1 | -39.9 | 74.0 | 83.4 | 94.8 | - | - | 1.1 |
| 110 | H1 | 8 | 61.3 | 54.2 | -63.9 | 88.5 | 219.6 | 218.3 | 197.5 | 133.9 | 1.1 |
| 110 | H2 | 8 | 69.6 | 57.7 | -77.5 | 106.4 | 288.5 | 311.5 | 180.7 | 99.1 | 1.0 |
| 110 | H3 | 8 | 80.3 | 69.6 | -86.5 | 109.7 | 385.2 | 391.2 | 132.8 | 80.7 | 1.0 |
| **all** | level | 39 | 27.5 | 27.8 | -46.3 | 77.9 | 83.5 | 88.7 | - | - | 1.2 |
| **all** | H1 | 88 | 61.8 | 56.0 | -79.5 | 106.4 | 269.4 | 318.9 | 172.8 | 169.7 | 1.2 |
| **all** | H2 | 90 | 76.4 | 66.0 | -94.7 | 118.1 | 383.8 | 427.2 | 182.5 | 140.3 | 1.0 |
| **all** | H3 | 82 | 82.8 | 71.9 | -104.2 | 126.7 | 452.4 | 518.2 | 144.9 | 121.3 | 1.0 |

## Questions for you

1. Obstacle heights: what were the real bar heights before and after Test 105 (task 1)? Was the obstacle or its marker mount changed between 104 and 105? Is the 20 mm marker-to-top offset right for both set-ups?
2. `order_randomized`: "no" (blocked repeats) or "blocks" (block order counterbalanced between participants)? And please confirm `sex`.
3. The Dot foot-sensor position on the shoe (distance from the toe tip, height above the sole): with the measured ankle-to-toe length it would let the toe vector be measured instead of fitted (task 3).
4. Should the drift flag stay in `include_ml`, or should `include_ml_noflag` be the default?
5. Level rows: add FeatureLog Level_Walk strides as extra level rows (different location definition), or keep the current ones?
