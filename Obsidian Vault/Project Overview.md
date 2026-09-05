---
tags: [overview]
---

# Project Overview

## The question
How do people **cross obstacles** while walking — how high and how the foot is lifted,
and how the body stays balanced — analysed per **limb role** (leading vs trailing leg),
per **body side** (left/right), and per **obstacle terrain** (height × depth).

Insufficient foot clearance and poor rotational balance are major causes of trips
and falls, so the headline measures are:
- **Foot clearance** — how high the foot is lifted over each obstacle (see [[Step 5 - Obstacle Features]]).
- **Joint kinematics** — hip/knee/ankle and now shoulder/elbow angles (see [[Step 3 - Dot vs Awinda Sync]]).
- **Whole-body angular momentum (WBAM)** — a dynamic-balance measure (see [[Step X - Angular Momentum]]).

## Measurement systems
Three systems record the same trials (see [[Data and Sensors]]):
- **Xsens Awinda** IMUs → fed into **OpenSim** (Rajagopal 2015 model) for joint angles.
- **Movella Dot** IMUs → gait-event detection and a foot-trajectory reconstruction.
- **WorldViz PPT** cameras → optical marker positions ([[Camera Tracking (WorldViz PPT)]]).

## Organisation
Everything is keyed by **`Test N`** (one experimental session per number). Raw data lives
in `Data/`, all outputs in `Results/`. The MATLAB code lives in `Analysis/` and is run
from there. See [[Pipeline Workflow]] and [[Outputs and File Formats]].

## The musculoskeletal model
**Rajagopal 2015** (`Analysis/Model/Rajagopal_2015.osim`). Full body incl. arms:
- Shoulder = `acromial` joint → `arm_flex`, `arm_add`, `arm_rot`
- Elbow = `elbow` joint (humerus→ulna) → `elbow_flex`
- Forearm/radioulnar = `pro_sup`; wrist = `radius_hand`

Arm IMUs were added to capture shoulder/elbow motion — see [[Session Changelog]].

Related: [[Conventions and Glossary]]
