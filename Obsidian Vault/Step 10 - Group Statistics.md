---
tags: [step, group, statistics, significance, spss]
aliases: [step10, group statistics, stats]
---

# Step 10 — Group Statistics

**File:** `Analysis/step10_group_statistics.m`
Runs the **group-level statistics** after step9. Reads `G.perParticipant` (one value per
participant × condition for every parameter) and tests the obstacle-crossing design.

## Design — Leading & Trailing are SEPARATE classes
**Leading and Trailing limbs are analysed independently** (no Role factor, no Leading-vs-Trailing
comparison): every test runs within Leading, then within Trailing. Within each class the design is
**Width**(W1=5cm, W2=15cm) × **Height**(H1,H2,H3) over the 6 obstacles; `Level_Walk` = baseline.
n = 9 (101–109).

## Tests (per parameter, per class)
- **Primary = non-parametric** (robust at n=9): **Friedman** (obstacle Height; and an omnibus across the
  6 obstacles), **Wilcoxon signed-rank** (Width, and crossing-vs-Level_Walk), effect sizes (Kendall's W, r).
- **Parametric alongside:** **Width×Height RM-ANOVA** (`fitrm`/`ranova`, Greenhouse–Geisser, partial η²).
- **Normality** (Lilliefors); **FDR** (Benjamini–Hochberg) across parameters, per effect, within each class.

## Parameters covered (~37)
Tier-1 clearance (toe/heel/min, take-off, landing), spatiotemporal (stride, cadence, speed), joint **ROM**
+ joint **MAX/MIN** (hip/knee/ankle), segment tilt ROM (thigh/shank/foot), named **peak angles** (11), and
**peak timing vs clearance** (joints + segments). Joint max/min reflect the hand-calculated values from
[[Step 9 - Group Crossing Analysis]] (`manualJointValues.m`).

## Outputs (`Results/Group Analysis/Statistics/`)
**SPSS-friendly: each table is its OWN single-sheet `.xlsx` file** (SPSS can't pick a sheet):
- `GroupStats_<cohort>_Wide.xlsx` — one row/participant, all parameter×condition columns (RM-ANOVA ready)
- `GroupStats_<cohort>_Long.xlsx` — one row/participant×condition (Test, Width, Height, Role + params)
- `GroupStats_<cohort>_Descriptives.xlsx` — mean±SD per condition, every parameter
- `GroupStats_<cohort>_Results_Leading.xlsx` / `_Results_Trailing.xlsx` — per-class test results (RM-ANOVA
  p's, Friedman Height + omnibus, Wilcoxon Width, vs-Level, FDR, effect sizes)
- `GroupStats_<cohort>_Report.md` — Leading & Trailing significance sections (non-parametric + RM-ANOVA)
- `Figures/` — `pvalue_heatmap.png` (param × effect, **Leading | Trailing** halves) + `dist_<group>.png`
  (6 obstacles 11–23 on x, Leading/Trailing boxes, per-class vs-level stars + obstacle omnibus, outliers
  hidden, step9 `plotStyle` template). Figures stay open after the run.

## Headline findings (n=9, FDR)
- **Crossing ≫ level walk** in both classes for most kinematics (ROM, peak angles, stride, cadence).
- **Obstacle height**: Trailing shows far more height-driven effects than Leading (trailing limb adapts
  more, clearing without vision); segment tilt ROM, hip/knee, cadence/speed scale with height.
- **Width**: few effects in either class.

Prev: [[Step 9 - Group Crossing Analysis]] · back to [[Home]]
