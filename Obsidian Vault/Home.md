---
tags: [moc, home]
aliases: [Index, Start Here, MOC]
---

# 🏠 Obstacle Crossing Project — Home

Map of content for the **IMU + OpenSim + camera** analysis of obstacle crossing gait.
Open this folder as an Obsidian vault; every note links to the others.

## Start here
- [[Study Rationale and Goal]] — 🎯 why we run this: segment angles + foot placement → wearable haptic feedback
- [[Project Overview]] — what the study is and why
- [[Pipeline Workflow]] — the end-to-end order and how to run it
- [[Data and Sensors]] — Awinda, Dot, and camera systems + the sensor map
- [[Conventions and Glossary]] — axes, terrain labels, terminology
- [[Session Changelog]] — summary of the latest work

## The IMU pipeline (steps 1–4)
1. [[Step 1 - OpenSense IK]] — raw Awinda → OpenSim inverse kinematics (+ auto `.mtb` conversion)
2. [[Step 2 - Joint Angle Viewer]] — inspect the IK joint angles
3. [[Step 3 - Dot vs Awinda Sync]] — compare + sync both IMU systems, export combined data
4. [[Step 4 - Segmentation (ZVP)]] — gait events (ZVP, toe-off, heel-strike) + stride segmentation + foot trajectory

> [!warning] Step 5 removed
> The old **Step 5 - Obstacle Features** relied on the app terrain labels + Dot "Logger" leading-leg log, which were unreliable. It is deleted. Obstacle type + leading/trailing now come from the **camera** (CV-side step 3 crossings), consumed by **Step 8**. Level-walk strides still come from the app FeatureLog.

## The camera pipeline (steps 6–9) ✅ integrated
> 🎉 See [[Camera Pipeline - Achievements]] for the full story.
6. [[Step 6 - Camera Sync and Viewers]] — sync camera markers to the 60 Hz IMU grid + interactive viewers
7. [[Step 7 - Camera Stride Segmentation]] — cut camera foot markers into strides on the IMU ZVPs
8. [[Step 8 - Leading-Trailing Features (Camera)]] — **camera-driven** leading/trailing + obstacle-type classification of all signals
9. [[Step 9 - Crossing Parameters]] — foot placement + height/min clearance per crossing

## Add-on
- [[Step X - Angular Momentum]] — whole-body + segmental angular momentum (`stepX_angular_momentum.m`)

## Camera reference
- [[Camera Tracking (WorldViz PPT)]] — optical marker position tracking (+ CV-side `refine_trajectory`)
- [[Camera Sync Strategy]] — how the camera is synced to the IMUs and segmented (now realized)

## Reference
- [[Outputs and File Formats]] — what each step writes and how to read it
- [[Heading Drift and De-drift]] — the IMU heading-drift problem and the anatomical heading-lock fix

---
> [!note] Three data streams
> **Awinda** (Xsens, 40 Hz), **Dot** (Movella, 60 Hz), and **Camera** (WorldViz PPT, ~60 Hz logged).
> See [[Data and Sensors]].
