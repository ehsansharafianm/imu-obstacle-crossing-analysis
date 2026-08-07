---
tags: [moc, home]
aliases: [Index, Start Here, MOC]
---

# 🏠 Obstacle Crossing Project — Home

Map of content for the **IMU + OpenSim + camera** analysis of obstacle crossing gait.
Open this folder as an Obsidian vault; every note links to the others.

## Start here
- [[Project Overview]] — what the study is and why
- [[Pipeline Workflow]] — the end-to-end order and how to run it
- [[Data and Sensors]] — Awinda, Dot, and camera systems + the sensor map
- [[Conventions and Glossary]] — axes, terrain labels, terminology
- [[Session Changelog]] — summary of the latest work

## The analysis steps
1. [[Step 1 - OpenSense IK]] — raw Awinda → OpenSim inverse kinematics (+ auto `.mtb` conversion)
2. [[Step 2 - Joint Angle Viewer]] — inspect the IK joint angles
3. [[Step 3 - Dot vs Awinda Sync]] — compare + sync both IMU systems, export combined data
4. [[Step 4 - Segmentation (ZVP)]] — gait events + stride segmentation + foot trajectory
5. [[Step 5 - Obstacle Features]] — leading/trailing limb, terrain, foot clearance
6. [[Step 6 - Angular Momentum]] — whole-body + segmental angular momentum

## Third measurement system (in progress)
- [[Camera Tracking (WorldViz PPT)]] — optical marker position tracking
- [[Camera Sync Strategy]] — how the camera will be synced to the IMUs and segmented

## Reference
- [[Outputs and File Formats]] — what each step writes and how to read it

---
> [!note] Three data streams
> **Awinda** (Xsens, 40 Hz), **Dot** (Movella, 60 Hz), and **Camera** (WorldViz PPT, ~60 Hz logged).
> See [[Data and Sensors]].
