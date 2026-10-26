---
tags: [step, group, statistics, significance, spss]
aliases: [step10, group statistics, stats]
---

# Step 10 — Group Statistics

**File:** `Analysis/step10_group_statistics.m`
Runs the **group-level statistics** after step9. Reads `G.perParticipant` (one value per
participant × condition for every parameter) and tests the obstacle-crossing design.

## Design
Within-subject **Width**(W1=5cm, W2=15cm) × **Height**(H1,H2,H3) × **Role**(Leading,Trailing);
`Level_Walk` = baseline. n = 9 (101–109).

## Tests (per parameter)
- **Primary = non-parametric** (robust at n=9): **Friedman** (obstacle Height), **Wilcoxon signed-rank**
  (Width, Role, and crossing-vs-Level_Walk), with effect sizes (Kendall's W, r = Z/√N).
- **Parametric alongside:** **Width×Height×Role RM-ANOVA** (`fitrm`/`ranova`, Greenhouse–Geisser p,
  partial η² for Height).
- **Normality** (Lilliefors) flagged to justify the non-parametric emphasis.
- **FDR** (Benjamini–Hochberg) across parameters, per effect.

## Parameters covered (~37)
Tier-1 clearance (toe/heel/min, take-off, landing), spatiotemporal (stride, cadence, speed), joint **ROM**
+ joint **MAX/MIN** (hip/knee/ankle), segment tilt ROM (thigh/shank/foot), named **peak angles** (11), and
**peak timing vs clearance** (joints + segments). Joint max/min reflect the hand-calculated values from
[[Step 9 - Group Crossing Analysis]] (`manualJointValues.m`).

## Outputs (`Results/Group Analysis/Statistics/`)
- **`GroupStats_<cohort>_SPSS.xlsx`** — sheets: **Wide** (one row/participant, SPSS-ready for RM-ANOVA),
  **Long**, **Descriptives** (mean±SD per condition), **RM_ANOVA**, **NonParam**, **vs_LevelWalk**.
- **`GroupStats_<cohort>_Report.md`** — significant-effects summary + full non-parametric & RM-ANOVA tables.
- **`Figures/`** — `pvalue_heatmap.png` (param × {Height,Width,Role,vs Level}) + `dist_<group>.png`
  distribution boxplots (Height×Role) per parameter group.
- Command-window summary of significant effects.

## Headline findings (n=9, FDR)
- **Crossing ≫ level walk**: 22 parameters differ (ROM, peak angles, stride, cadence, clearance).
- **Height**: segment tilt ROM (shank/thigh), hip ROM/angle, cadence, speed, toe clearance ↑ with height.
- **Role**: pervasive Leading vs Trailing differences (placement, ankle/segment ROM, timing).
- **Width**: fewer effects (toe clearance, landing distance, shank ROM).

Prev: [[Step 9 - Group Crossing Analysis]] · back to [[Home]]
