# ML feasibility summary: can wearable (Dot IMU) features tell the obstacle?

> **Latest (MATLAB):** see `MATLAB/STORY_SUMMARY.md`, which gives the full story and the numbers:
> - **Two foot IMUs:** 92 % height accuracy on a new person.
> - **Calibration:** 1 labelled crossing per height gives 88 %; with no calibration, 73 %.
> - **Answering only when confident:** 97.7 % accuracy on 67 % of crossings.
> - **Camera-free, end-to-end pipeline:** 86 % of crossings correct.
> - **Height in cm:** MAE 2.4 cm.
> - **Foot lift:** +10.1 mm per cm of obstacle (mixed-model 95 % CI 9.4–10.8), with a constant safety margin.
> - **Personal signature:** one crossing identifies the walker with 99 % accuracy; the personal margin explains the generic ceiling.
> - **Width:** behaviourally invisible, even to the camera.
> - **Clearance:** not estimable from the IMU.

Paste this into a new chat to get the results evaluated. Supporting files are in `Results/ML Models/`: `ml_report.md` (all tables), `ml_results.csv` (every run) and 3 figures. Code: `Analysis/ML/python/crossing_ml.py`. Generated 2026-10-30.

## Purpose
This is a feasibility test, not a product. The question is whether the wearable signals alone carry information about the obstacle in a participant the model has never seen. It also asks which segments and which limb carry it, as candidate targets for haptic feedback.
- **Q1:** Can the model predict obstacle height?
- **Q2:** Which segment or limb carries the information?
- **Q3:** Is the leading limb alone enough?
- **Q4:** Can it predict obstacle width?

## Data
- **Participants:** 10 young adults (6 F, 4 M).
- **Obstacles:** 6 = 3 heights (H1/H2/H3 = 10/20/30% of leg length) × 2 widths (W1 = 5 cm, W2 = 15 cm), each with about 5 repeats, run in blocks.
- **Unit of analysis:** one row per crossing. Both limbs are in the same row, named by role (lead_ / trail_).
- **Rows used:** 260 obstacle crossings that passed quality checks (`include_ml` = 1).
  - H1 / H2 / H3 = 88 / 90 / 82.
  - W1 / W2 = 127 / 133.
- **Inputs:** 110 features from Movella Dot IMUs on the thigh, shank and foot. No camera, labels, timing or block columns.
  - **Segment tilt angles:** max, min, ROM, timing and offset-corrected peaks, plus angular velocity.
  - **Foot acceleration.**
  - **Foot trajectory (ZHC):** a per-stride integrated foot path, giving peak height, heights at 25/50/75% of swing, velocities and positions.
  - **Spatiotemporal:** stride length, speed, cadence, swing and stance time.

## Method
- **Test on unseen participants:** leave-one-participant-out, i.e. train on 9, test on the 10th, 10 folds. Imputation, scaling, feature selection and the model are all fitted on the training participants only.
- **Main model:** L2 logistic regression with C = 0.1, fixed before looking at the results (no tuning). Check model: random forest (500 trees).
- **"Calibrated" features:** each participant's own level-walk median is subtracted, and lengths are divided by leg length. A device could get this from a short normal-walking calibration. Raw features were also run.
- **Metric:** balanced accuracy. Chance is 33% for height and 50% for width.
- **Significance:** permutation test with labels shuffled within each participant (1000 permutations for the main runs, 300 for the feature groups). The 95th percentile of the null is about 38% for height and about 55% for width.

## Results

### Q1 – Height: yes, above chance on unseen participants
| features | logistic, calibrated | logistic, raw | forest, calibrated | perm. p |
|---|---|---|---|---|
| all (110) | 53.7% | 53.3% | 58.1% | < 0.001 |
| lead only (57) | **62.1%** | 56.4% | 60.1% | < 0.001 |
| trail only (52) | 49.1% | 53.6% | 61.1% | < 0.001 |

The errors are almost all between neighbouring heights.

Confusion matrix, all features (rows = true, columns = predicted):

|  | H1 | H2 | H3 |
|---|---|---|---|
| H1 | 55 | 30 | 3 |
| H2 | 25 | 35 | 30 |
| H3 | 1 | 32 | 49 |

H1 and H3 were confused only 4 times in 260 crossings.

### Q2 – Which segment and limb (logistic, calibrated, height)
| group | both limbs | lead | trail |
|---|---|---|---|
| foot angle | 61.2% | **66.5%** | 53.3% |
| ZHC foot trajectory | 56.3% | 60.4% | 57.9% |
| thigh | 58.3% | 53.7% | 41.0% |
| shank | 52.3% | 43.3% | 51.2% |
| spatiotemporal | 53.7% | 44.3% | 54.5% |
| foot acceleration | 44.9% | 38.2% | 47.0% |

All groups are above the permutation null (p ≤ 0.017). The strongest groups are the lead foot (its orientation and its lift height) and the thigh. The shank is weaker, and foot acceleration is close to chance.

### Q3 – Lead limb alone: yes
- Lead-only features (62.1%) beat all features (53.7%). With 110 features and 260 rows the full model overfits.
- **One feature, the lead foot's peak height (from the ZHC trajectory), gives 65.9% alone.** It was picked in 9 of 10 training sets.
- **Stable small set (k = 3–5, 62–64%):** lead foot peak height, lead thigh max flexion (raw and offset-corrected), and lead foot height at 25–50% of swing.

### Q4 – Width: mostly no
- All features reach 57.8% (p = 0.015; chance 50%, null 95th percentile 55.6%). The forest reaches 59.5%.
- Half of the W2 crossings are predicted as W1. The result is statistically above chance but practically weak, which supports width as something a wearable cannot see well.

### Per participant (height, logistic, calibrated)
| features | 101 | 102 | 103 | 104 | 105 | 106 | 107 | 108 | 109 | 110 |
|---|---|---|---|---|---|---|---|---|---|---|
| all | 61% | 40% | 72% | 31% | 68% | 52% | 74% | 38% | 42% | 58% |
| lead only | 67% | 50% | 55% | 42% | 72% | 62% | 78% | 85% | 58% | 54% |

Participants differ a lot (42–85% lead-only).

### Sensitivity
Ignoring the IMU drift flag (264 rows) gives height accuracy of 54.3% with all features (vs 53.7%).

## Caveats
1. **The camera locates the crossing.** Lead/trail roles and the crossing stride come from the camera. A Dot-only detector found 90% of crossings and agreed on all of them, but it was not used here.
2. **n = 10 is small.** The results show feasibility only, and the spread between participants is large.
3. **Obstacles were run in blocks** (5 consecutive repeats, block order varying by participant). Testing on unseen participants and leaving block and order out of the features limits this, but anticipation within a block is possible.
4. **Feature design choices:** the swing window runs from IMU toe-off to heel-strike, and the lead heel-strike fires about 50 ms early. Toe height was left out because the sensor-to-toe geometry is still provisional.
5. **Measured obstacle heights** differ from the nominal ones because the marker mount changed between sessions 104 and 105. This does not affect the ML labels, which are the design classes H1/H2/H3.

## Follow-up checks (`ml_followup.md`, `fig_cueing_time.png`, `fig_learning_curve.png`)
95% CIs come from a participant bootstrap (2000 resamples). Same 260 rows and the same model as above.
- **Bootstrap CIs (height):**

  | model | accuracy | 95% CI |
  |---|---|---|
  | all features | 53.7% | 45–63 |
  | lead only | 62.1% | 55–70 |
  | trail only | 49.1% | 40–58 |
  | lead foot IMU only | 57.6% | 48–69 |
  | lead thigh IMU only | 53.7% | 44–64 |
  | lead shank IMU only | 43.3% | 38–48 |
  | lead foot peak height alone | 63.6% | 51–75 |

  - Lead-only minus all: −0 to +18 points.
  - Lead only is better in 8 of 10 participants, by +4.3 points on average without 108.
  - Width: 57.8% (53–62).
- **Cueing window (Dot events):** in every crossing the lead limb finishes before the trailing foot leaves the floor.
  - Lead foot apex → trail toe-off: median 683 ms (IQR 600–767).
  - Lead landing → trail toe-off: 417 ms (317–517). It grows with height: 342 / 433 / 483 ms for H1 / H2 / H3.
  - Trail toe-off → trail foot apex: only about 67 ms. So a cue has to arrive before the trailing toe-off.
- **Time-resolved prediction, lead limb only:**
  - Approach strides alone: 34% (chance). The obstacle is not visible in the approach.
  - At lead toe-off: 42%.
  - From about 40–60% of the lead swing (around the foot apex, about 690–750 ms before trail toe-off): about 59–61%. This is a plateau; waiting for lead landing adds nothing.
- **Learning curve:**
  - Lead-only and the single feature rise only slightly from 6 to 9 training participants (+1.9 and +0.6 points). All features does not improve (−2.4).
  - At this feature level, more participants would add little. The limit is the features and between-person differences, not n alone.
- **Ordinal model:** about the same accuracy as nominal (lead only 63.3% vs 62.1%). Mean error is about 3.8–4.7% of leg length; H1↔H3 errors stay at 2–4 crossings.
- **Confidence, lead-only model:** if it predicts only when the top probability is at least 0.6, it covers 70% of crossings at 68% accuracy. At 0.7 it covers 53% at 73%.

## Separate lead / trail models (`ml_limbs.md`, `fig_limbs.png`)
- **Setup:** the leading and trailing limbs each get their own model and are never mixed. "Fusion" averages the two models' class probabilities at the end.
- **Second normalisation, "self":** each person is scaled to their own median and IQR over their crossings. This uses no labels, but it does need a set of the person's crossings that spans several obstacles.

| target (chance) | level-walk norm, logistic: lead / trail / fusion | self norm, best (random forest): lead / trail / fusion |
|---|---|---|
| height (33%) | 62 / 49 / 56% | **87 / 86 / 90%** |
| width (50%) | 54 / 57 / 56% | 60–65% at best |
| 6 obstacles (17%) | 29 / 28 / 29% | 48 / 57 / **60%** (height right 91%, width right 62%) |
| obstacle vs level walk (50%) | – | about 100% (raw or self) |
| leading vs trailing, one limb at a time (50%) | **100%** with every setting | 100% |

- **Leading vs trailing (100%) is real biomechanics, not a bug.** Single features separate the limbs almost perfectly (AUC ≥ 0.98): the trailing foot peaks at 17% of its swing vs 54% for the lead; thigh max flexion is 47° vs 84°; stance time differs. This was tested only on strides already known to be crossings.
- **The self normalisation needs data.** The new person's median and IQR were computed from only n unlabelled crossings, and the model was tested on the rest:

  | n crossings | random n | first n walked |
  |---|---|---|
  | 3–6 | 62–73% | 57–65% |
  | 10 | 76–81% | 65–66% |
  | 15 | 78–84% | 79–81% |

  So about 10–15 mixed crossings are needed. With fewer, it is no better than the level-walk calibration.
- **Personal calibration (k labelled crossings per height, weighted ×10):**

  | normalisation | model | k = 0 | k = 1 | k = 2 | k = 3 |
  |---|---|---|---|---|---|
  | level walk | lead | 62% | 72% | 77% | 80% |
  | level walk | fusion | 56% | 75% | 81% | 83% |
  | self | lead | 80% | – | – | 83% |
  | self | fusion | 81% | – | – | 87% |

- **Permutation tests (300 shuffles):** every height, 6-obstacle and role result has p ≤ 0.003. Width is significant only with the self normalisation (p = 0.003); with the level-walk normalisation p = 0.04–0.11.
- **Caveat:** the "best" column picks the best of several settings, which is optimistic. The pre-specified main analysis is logistic regression with level-walk normalisation.

## Best setting, chosen honestly (`ml_settings.md`, `fig_settings.png`)
- **Nested selection.** For each unseen participant, the best of 30 settings was chosen using the other 9 participants only. The settings were normalisation (level / self) × model (logistic regression at 4 regularisation strengths / random forest) × limb (lead / trail / fusion).
  - **Nested height accuracy: 89.2% (95% CI 84–93).** Every fold chose the same setting: self normalisation, random forest, lead + trail fusion.
  - Per participant: 73–97% (lowest are 108 at 73% and 102 at 80%).
- **Segment ranking still holds with the self normalisation** (random forest):

  | segment | lead | trail |
  |---|---|---|
  | foot angle | 88% | 85% |
  | ZHC trajectory | 85% | 85% |
  | thigh | 77% | 45% |
  | shank | 49% | 78% |
  | foot acceleration | 38% | 54% |

  The foot is the strongest site for both limbs. The thigh works on the leading limb and the shank on the trailing limb.
- **Timing with the self normalisation** (lead limb, random forest):

  | point in the lead swing | about how long before trail toe-off | accuracy |
  |---|---|---|
  | toe-off | 980 ms | 52% |
  | 40% of swing (just before the lead foot apex) | 750 ms | 80% |
  | 70–90% of swing | 470–580 ms | 87–89% |

  The information is mostly available around the lead foot apex and keeps improving slightly until just before landing. This is still well before the trailing foot leaves the ground.
- **Learning the normalisation during use (causal):** each crossing is normalised using only the person's earlier crossings, so accuracy depends on how much history the device has.

  | earlier crossings available | lead only | lead + trail fusion |
  |---|---|---|
  | 5 | 67–68% | 69–71% |
  | 10 | 71–72% | 74–75% |
  | 15 | 75–78% | 83% |
  | 20 | 72–81% | 84–88% |

  This is conservative here, because the blocked order means early history covers few obstacles.

## Planned next steps (ML)
1. **Curve features:** time-normalised swing curves (PCA or MiniRocket) instead of summary values.
2. **Ordinal model:** report the height error in % of leg length.
3. **Few-shot personalisation:** add 1–3 labelled crossings from the new person to the training data.
4. **SHAP:** explain the best model.
5. **Stability selection:** find a minimal sensor and feature set.
6. **Learning curve:** train on 3 to 9 participants.
7. **Time-resolved prediction:** accuracy at toe-off, mid-swing, and so on.
8. **Confidence-based prediction:** predict only when the model is confident.

## Questions for the reviewer
- Is the evaluation sound for a claim about unseen participants (leakage, choice of C, permutation scheme)?
- Is it fair to call 54–66% vs 33% chance "height is detectable", given the per-participant spread?
- Is the lead-only > all-features result best explained by overfitting? Should it be reported as the main model?
- Which next steps would strengthen the paper most at n = 10?
