# What wearable IMUs reveal about obstacle crossing — summary of the MATLAB analyses

**Study:** 10 young adults, with Movella Dot IMUs on the thigh, shank and foot of both legs. They crossed 6 obstacles: 3 heights (10 / 20 / 30 % of leg length) × 2 widths (5 / 15 cm), about 5 repeats each.

**How the results were tested:** every accuracy below is on a participant the model never saw (leave-one-participant-out). Chance is 33 % for height and 50 % for width. CI = 95 % participant-bootstrap interval.

## The story in one paragraph

People clear an obstacle by lifting the foot by about the obstacle height: **+10 mm per cm of obstacle, 95 % CI 9.4–10.8**, for the leading foot. This lift comes from thigh flexion on the leading leg and heel-up on the trailing leg. Meanwhile they keep a nearly constant safety margin. How much extra each person lifts for *any* obstacle is very personal: it varies across people by two-thirds of the step between two heights. Every person also has a strong walking "signature": one crossing identifies the walker with 99 % accuracy. This is why a generic model reaches only about 62–73 %, but **one foot IMU per leg recognises obstacle height on a new person with about 92 % accuracy once the device has seen some of that person's crossings.** The information is available about 0.7 s before the trailing foot leaves the ground, so there is time to cue it. In real time, using only the leading leg, about 3 in 4 cues are correct (about 80 % of the cues given when the device answers only when confident). The whole pipeline (finding the crossing, telling which leg led, classifying the height) runs without any camera. Width is not detectable, and that limit is behavioural: people barely change how they cross for a 5 vs 15 cm obstacle.

## Contributions and key numbers

### 1. How people scale the crossing to the obstacle (biomechanics)
*Report: `ml_story_matlab.md` §3; figure: `fig_story_strategy.png`.*

Mixed model with a random intercept and slope per participant:

| what changes with obstacle height | per cm of obstacle | 95 % CI |
|---|---|---|
| lead foot lift | **+10.1 mm** | 9.4–10.8 |
| trailing foot lift | **+11.1 mm** | 9.7–12.6 |
| lead thigh flexion | +1.19° | – |
| trailing shank backward tilt (heel-up) | −1.19° | – |
| camera safety margin, lead | **−0.7 mm** (not significant) | −1.8 to +0.4 |
| camera safety margin, trail | −2.3 mm (not significant) | −4.7 to +0.1 |

People lift by about the obstacle height and keep their margin.

- **The first crossing of a new obstacle is more cautious:** lead foot lift is +12 mm (CI +5 to +20) above the mean.
- **The leading leg is *not* chosen by dominance:** only 45 % of crossings led with the dominant leg, and most people alternate.
- **The two legs vary independently within a crossing** (r ≈ 0.1 after removing the obstacle effect). The leading leg tells you the obstacle, not the trailing leg's error.

### 2. Where and when the obstacle is encoded (§1, `fig_story_map.png`)

| limb | where the height information is | eta² | when |
|---|---|---|---|
| leading | foot height | 0.62 | mid-swing (48 %), around the apex |
| leading | thigh flexion | 0.45 | 62 % of swing |
| trailing | foot height | 0.76 | 20 % of swing |
| trailing | shank tilt | 0.66 | at push-off (4 %) |

Width leaves no trace in any signal (eta² ≤ 0.08).

### 3. The personal signature and the personal margin explain the accuracy limits (§2, §3.4, §5; `fig_story_person.png`, `fig_story_embed.png`)

- **One crossing identifies the walker with 99.2 % accuracy.** The person explains more variance than the obstacle height in 99 of 110 features.
- **The 2-D map of all crossings:** it clusters by **person** (silhouette 0.48), and orders by **height** only after person scaling (0.26).
- **The personal obstacle margin varies across people:** SD 64 mm (lead lift), against a 98 mm step between two heights.
- **It is barely predictable** from ordinary walking (r = 0.43) or leg length (r = 0.20).
- **So:** a generic model has a ceiling, and a short exposure to the person's own crossings removes it.

### 4. Recognising obstacle height (`ml_explore_matlab.md`, `ml_device_matlab.md`, `ml_story_matlab.md` §4/§6)

| setting | accuracy |
|---|---|
| generic model, 57 summary features (lead leg) | 62 % |
| **generic model, 13 clearance-shape features** (lead foot: how long / how far the foot stays high, apex position, foot tilt at the apex) | **73 %** (p = 0.003) |
| honest nested selection among generic settings | 69 % (CI 58–80) |
| **2 foot IMUs, person scaling** (lead + trail models, soft vote) | **92.3 % (CI 87–96)** |
| all 6 IMUs, person scaling | 91.2 % |
| honest nested selection over 36 settings | 91.5 % (CI 86–97; worst participant 73 %) |
| deep learning (1D CNN on the raw swing curves, person scaling) | 88 % |
| height as a number (regression, cm) | **MAE 2.4 cm, r = 0.91** |

### 5. A device design (`ml_device_matlab.md`, `fig_device.png`)

**Sensors:**

| configuration | accuracy |
|---|---|
| two foot IMUs | **92 %** |
| one foot IMU on one leg | 83–91 % |
| two thigh IMUs | 80 % |
| two shank IMUs | 79 % |

The foot is the best site. The thigh carries the leading leg's information and the shank the trailing leg's.

**Calibration needed from a new user:**

| calibration | accuracy |
|---|---|
| none | 56–73 % |
| 1 labelled crossing of ANY height (physics-informed offset model) | 80 % |
| 1 labelled crossing per height | 88 % |
| 10–15 unlabelled crossings | 81–85 % |
| all of a session's crossings | 92 % |

**Answer only when confident:**

| answer when probability is at least | crossings answered | accuracy on them |
|---|---|---|
| 0.6 | 79 % | 96.6 % |
| 0.7 | 67 % | 97.7 % |
| 0.8 | 46 % | 98.3 % |

**Training-set size:** a model trained on only 2–3 people already reaches about 88–89 %. More participants won't fix the remaining errors; personal calibration does.

**Timing:** height is about 80 % known by the lead foot apex, about 0.7 s before trailing toe-off (`ml_report_matlab.md` §2.2, §4.3).

**In a real session with mixed obstacles** (`ml_realworld_matlab.md` R1, `fig_realworld.png`): each participant's crossings were shuffled 30 times. The device starts with the generic model and switches to person scaling learned from the crossings it has already seen (no labels).

| crossings walked | mixed order | blocked study order |
|---|---|---|
| 1–5 | 72 % | 70 % |
| 6–15 | **79 %** | collapses to 46–56 % |
| 16 onwards | **90 %** | 89 % |

In the blocked order the early history covers only one or two obstacles, which is why it collapses in the middle. Mixed obstacles are the realistic case, so our blocked-order "learning during use" numbers are pessimistic.

**Why some people are harder** (R3): once the device knows the person, accuracy follows how consistently they lift the **trailing** foot at a given height (r = 0.77 over the 10 participants). The weakest participant, 108 (73 %), has by far the least consistent trailing lift (d' 0.9 vs 2.1–4.5 for the others).

### 6. Fully wearable, no camera (`ml_stream_matlab.md`, `fig_stream.png`)

The pipeline uses all 7,250 strides of the sessions.

**Steps:**
1. Detect the crossings.
2. Pair them into lead and trail strides.
3. Classify the height.

**Results:**
- **Detection:** 98.7 % recall, 97.2 % precision.
- **End to end, all correct:** **86 %**, or 83.5 % of every crossing walked.
- **Learning during use:** 77 % after 15 crossings.

**Real time, for haptic cueing** (`ml_realworld_matlab.md` R2):
- **Detecting the leading-leg crossing at its foot apex** (online features only, over all 7,250 strides): **99 %** found, with about 3 false detections per session of about 725 strides.
- **Height cue from the leading-leg data available at that moment** (mixed order, the device learning as it goes):

| cue moment | time left before the trailing foot leaves the ground | correct cue | correct cue after 15 crossings | with a 0.6 confidence threshold |
|---|---|---|---|---|
| lead foot apex | ~0.7 s | **70 %** | 75 % | 79 % of the given cues are right; 30 % withheld |
| lead landing | ~0.4 s | **76 %** | 84 % | 82 % of the given cues are right; 25 % withheld |

- **The real-time cue is less accurate than the after-the-fact recognition** (~92 %), because only the leading leg's data exist when the cue must be sent. This is the honest number for a cueing device. A product would also confirm the crossing when the trailing foot starts its swing.

### 7. Limits (reported as findings)

- **Width is behaviourally invisible.**
  - For a 10 cm wider obstacle the crossing step grows by only about 4 cm.
  - Even the camera's foot placement classifies width at only 57 %. The IMU models reach 55–66 %.
  - **Side-to-side motion doesn't help** (`ml_lateral_matlab.md`, `fig_lateral.png`). I checked the sideways tilt and twist of the thigh, shank and foot, and the foot's outward path: they alone give 53 %, and the largest width effect is 6 % of the variance. People simply don't cross a 5 vs 15 cm obstacle differently in any direction.
- **The clearance margin cannot be estimated from the IMU** (r ≈ 0). Near-contact detection is weak (AUC 0.63–0.73), because the margin is nearly constant and its variation is not visible in the foot motion.
- **Self-training** (the model labelling the new user's crossings itself) **makes things worse** (54–67 %).
- **Comparing each crossing to the previous normal stride** doesn't help either (about 60 %). The personal margin is not visible in ordinary walking.

## Caveats
- **n = 10 young adults:** these are feasibility results. Confirm on new participants and older adults.
- **The clearance-shape features were designed after the first results** (a few iterations, guided by biomechanics), so a small optimism remains.
- **Person scaling assumes the user's crossings cover several heights.** "First n" crossings in the blocked protocol is the conservative case.
- **Obstacles were run in blocks.** The crossing order was never used as a feature.

## Files
Code (MATLAB), in `Analysis/ML/`:

| file | what it does |
|---|---|
| `build_crossing_master.m` | builds the dataset |
| `crossing_ml_matlab.m` | the main analyses |
| `crossing_ml_explore.m` | new features and models |
| `crossing_ml_story.m` | the biomechanical story |
| `crossing_ml_device.m` | sensors, calibration, confidence |
| `crossing_ml_stream.m` | the camera-free pipeline |
| `crossing_ml_realworld.m` | mixed-order sessions, real-time cueing, harder participants |
| `crossing_ml_lateral.m` | width from side-to-side motion |
| `mlTools.m` | shared building blocks |

Reports and figures are in this folder.
