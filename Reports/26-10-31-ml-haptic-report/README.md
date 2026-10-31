# ML and haptic-cue report (Tests 101-110)

## Open it in Overleaf

1. Overleaf: **New Project > Upload Project**, then choose `26-10-31-ml-haptic-report.zip`.
2. The main document is `main.tex`. Compiler: **pdfLaTeX** (the Overleaf default).
3. If references show "??", click **Recompile** once more.

## What is inside

- `main.tex`: preamble and document order.
- `sections/`: the text (`01_introduction` ... `07_appendix`; results are split into `04a`-`04f`).
- `tables/`: every table, generated from the analysis reports (`Results/ML Models/MATLAB/ml_*_matlab.md`) and the
  dataset files (`Results/ML Dataset/`), so the numbers are copied, not retyped.
- `figures/`: the 19 MATLAB figures (`Results/ML Models/MATLAB/fig_*.png`), all drawn by `Analysis/ML/crossing_ml_figures.m`
  in the plot template of the step 9 group figures (Arial, bold 16-pt labels and titles, 13-pt ticks, 2-pt axes box, no grid,
  blue = leading / orange = trailing limb, 300-dpi PNG).

## Source of the numbers

Full rerun of the nine MATLAB analyses (`Analysis/ML/crossing_ml_*.m`) on the rebuilt dataset
(`Analysis/ML/build_crossing_master.m`), 31 October 2026.
