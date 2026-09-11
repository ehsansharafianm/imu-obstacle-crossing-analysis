---
tags: [moc, rationale, goal, protocol]
aliases: [Goal, Rationale, Study Goal, Aims]
---

# 🎯 Study Rationale and Goal

> [!abstract] In one line
> Find which **lower-limb segment angles** (thigh / shank / foot) and **foot-placement distances** (lift-off / landing) respond most strongly to obstacle height — for the **leading** and **trailing** limbs — so they can drive a **wearable haptic-feedback** system for obstacle-crossing training.

## Rationale
The purpose of this experiment is to inform the design of a **wearable haptic-feedback system** for improving obstacle-crossing performance. Specifically, we aim to identify which **lower-limb segment angles** and **foot-placement variables** are the strongest candidates for real-time feedback and movement correction.

Previous obstacle-crossing studies have primarily examined **joint kinematics** (hip, knee, ankle angles) in relation to obstacle height. Although this identifies the joints involved in successful negotiation, joint angles are hard to estimate accurately in real time with wearables: they may need multiple sensors, accurate sensor-to-segment alignment, and assumptions about joint centres. Instructions based on joint angles may also not be intuitive or directly actionable.

**Segment angles** — the orientations of the thigh, shank, and foot — can be measured more directly with IMUs and can support more understandable feedback ("lift your thigh higher", "move your shank farther forward"). But it is unclear which segment angles respond most strongly and consistently to obstacle height, especially for the leading vs trailing limb.

Successful crossing also depends on **where each foot is placed** before and after the obstacle. The **lift-off distance** affects the available space and trajectory; the **landing distance** influences stability and preparation for the next step. These spatial adaptations are practical feedback targets — measurable with wearables and communicable as simple instructions ("lift earlier", "land farther beyond the obstacle").

This study therefore investigates how **lower-limb segment angles** and **horizontal foot-placement distances** change when participants cross obstacles of different **heights normalised to leg length**, analysing the **leading and trailing limbs separately**.

## Primary objectives
1. Which segment angle — **thigh, shank, or foot** — is most sensitive to changes in obstacle height.
2. Whether the **leading and trailing** limbs use different segment-level adaptations.
3. How obstacle height affects the **horizontal distance between the foot and obstacle at lift-off**.
4. How obstacle height affects the **horizontal distance between the obstacle and the foot at landing**.
5. Whether segment angles and foot-placement distances reflect adaptations previously reported using **joint kinematics**.
6. Which variables are **measurable, responsive, and user-modifiable** enough to serve as **real-time haptic-feedback targets**.

## Research questions
- Which lower-limb segment angle is most sensitive to increasing obstacle height?
- Do thigh, shank, and foot angles respond differently between the leading and trailing limbs?
- Does increasing obstacle height change how far **before** the obstacle participants lift each foot?
- Does increasing obstacle height change how far **beyond** the obstacle each foot lands?
- Which combination of segment angles and foot-placement distances best characterises successful crossing?
- Which variables are the best candidates for detecting an inadequate crossing strategy and delivering corrective haptic feedback?

## Hypotheses
1. Increasing obstacle height produces systematic changes in thigh, shank, and foot orientations.
2. **Thigh flexion** shows the largest and most consistent response to obstacle height, followed by shank orientation.
3. The **leading and trailing** limbs exhibit different segment-angle adaptations (different mechanical roles).
4. Participants modify **lift-off and landing distances** as obstacle height increases to keep clearance and stability.
5. Segment angles **combined with** lift-off/landing distances describe adaptations better than either alone.

## Practical significance
The results bridge laboratory joint-kinematics research and wearable obstacle-crossing training systems, helping determine:
- Which **body segment** to monitor
- Which **foot-placement distance** to evaluate
- Whether feedback should target the **leading limb, trailing limb, or both**
- **When** feedback should be delivered
- **What direction** of correction to communicate
- How feedback **thresholds** should change with obstacle height

## Spatial variable definitions (for the methods)
- **Lift-off distance** — horizontal distance from the relevant point of the foot to the obstacle when the foot leaves the ground.
- **Landing distance** — horizontal distance from the obstacle to the relevant point of the foot at initial contact.
- **Leading-limb** lift-off and landing distances.
- **Trailing-limb** lift-off and landing distances.

> [!note] Foot landmark convention (define in the protocol)
> Use a consistent landmark per distance — e.g. **toe** for the pre-obstacle (lift-off) distance and **heel** for the post-obstacle (landing) distance. Fix this in the experimental protocol.

---
How this maps onto the pipeline: leading/trailing per crossing and obstacle type come from the **camera** ([[Step 8 - Leading-Trailing Features (Camera)]], fed by the CV-side step-3 crossings); segment/joint angles and foot trajectories come from the IMU/OpenSim steps ([[Step 4 - Segmentation (ZVP)]]); foot-placement distances relative to the obstacle come from [[Step 9 - Crossing Parameters]]. See [[Project Overview]] and [[Pipeline Workflow]].
