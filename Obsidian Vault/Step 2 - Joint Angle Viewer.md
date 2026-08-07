---
tags: [step, viewer]
aliases: [step2, step2_plot_joint_angles]
---

# Step 2 — Joint Angle Viewer

**File:** `Analysis/step2_plot_joint_angles.m`
Interactive viewer of the IK joint angles from [[Step 1 - OpenSense IK]].

## What it does
- Loads the newest `IKResults/ik_*.mot`.
- One **checkbox per coordinate** (auto-generated from the `.mot` columns — generic, so any new
  joints appear automatically), Line / Scatter / Both style, per-curve colours, Save PNG.

## Default-on joints
Lower limb + upper limb: `hip_flexion`, `knee_angle`, `ankle_angle` (both sides), and
`arm_flex`, `elbow_flex` (both sides) — the shoulder/elbow were added when the arm IMUs went in
(see [[Session Changelog]]).

## In / out
- **In:** `Results/OpenSim Outputs/Test N/IKResults/ik_*.mot`.
- **Out:** joint-angle PNG in `Results/OpenSim Outputs/Test N/Figures/`.

Prev: [[Step 1 - OpenSense IK]] · back to [[Pipeline Workflow]]
