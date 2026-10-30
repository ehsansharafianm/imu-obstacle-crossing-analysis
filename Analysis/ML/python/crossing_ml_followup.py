"""Follow-up checks on the LOPO height models (run after crossing_ml.py; same rules).

  1. Cueing window   - time from the lead-limb events (toe-off, foot apex, landing) to the
                       trailing foot's toe-off and apex.
  2. Time-resolved   - height accuracy from lead-limb data available up to x %% of the lead swing
                       (swing curves cropped at x, plus the approach strides), mapped to the
                       time before the trailing foot leaves the floor.
  3. Bootstrap CIs   - participant-level bootstrap of balanced accuracy for the main and the
                       single-sensor / single-feature models, and paired differences.
  4. Learning curve  - accuracy vs number of training participants (2..9).
  5. Ordinal model   - Frank & Hall ordinal logistic; error in %% of leg length; confidence.

Same model as crossing_ml.py (calibrated features, L2 logistic C = 0.1, every fitted step
inside the training participants). Descriptive only; no tests on the biomechanics.
Reads  Results/ML Dataset/{Crossing_Master,Crossing_Curves}_YoungAdults.csv
Writes Results/ML Models/ml_followup.md, fig_cueing_time.png, fig_learning_curve.png
"""
from __future__ import annotations

import itertools
import sys
from datetime import datetime
from pathlib import Path

import numpy as np
import pandas as pd
from joblib import Parallel, delayed
from sklearn.metrics import balanced_accuracy_score
from sklearn.model_selection import LeaveOneGroupOut

sys.path.insert(0, str(Path(__file__).resolve().parent))
import crossing_ml as M                         # noqa: E402  (shared loading / model)

import matplotlib.pyplot as plt                 # noqa: E402  (backend set by crossing_ml)

CURVES = M.ROOT / "Results" / "ML Dataset" / "Crossing_Curves_YoungAdults.csv"
SIGNALS = ["thigh", "shank", "foot", "footacc", "zhc_h", "zhc_x"]
PRE_SWING = ["stride_len_app1", "stride_len_app2", "speed_approach", "lead_stance_time"]
CUTS = [0, 10, 20, 30, 40, 50, 60, 70, 80, 90, 100]
N_BOOT = 2000
LC_REPEATS = 40
PALETTE = [M.BLUE, M.ORANGE, M.AQUA, "#eda100"]


# ---------------- helpers ----------------
def boot_ci(y, pred, g, other=None, n=N_BOOT, seed=M.SEED):
    """Participant bootstrap of balanced accuracy (and of a paired difference with `other`)."""
    rng = np.random.default_rng(seed)
    P = np.unique(g)
    idx = {p: np.where(g == p)[0] for p in P}
    a, d = [], []
    for _ in range(n):
        i = np.concatenate([idx[p] for p in rng.choice(P, len(P), replace=True)])
        if len(np.unique(y[i])) < 2:
            continue
        s = balanced_accuracy_score(y[i], pred[i])
        a.append(s)
        if other is not None:
            d.append(s - balanced_accuracy_score(y[i], other[i]))
    out = (np.percentile(a, 2.5), np.percentile(a, 97.5))
    if other is not None:
        out += (np.percentile(d, 2.5), np.percentile(d, 97.5))
    return out


def curve_block(C, limb, sig):
    cols = [c for c in C.columns if c.startswith(f"{limb}_{sig}_p")]
    return C[cols].to_numpy(float)              # n x 51, 0..100 % swing


def cut_features(C, cut):
    """Lead-limb features from the swing curves cropped at `cut` % swing."""
    k = int(round(cut / 2))                     # index of the cut (0:2:100)
    F = {}
    for sig in SIGNALS:
        X = curve_block(C, "lead", sig)[:, : k + 1]
        F[f"{sig}_at"] = X[:, -1]
        if k >= 1:
            F[f"{sig}_max"] = np.nanmax(X, axis=1)
            F[f"{sig}_min"] = np.nanmin(X, axis=1)
            F[f"{sig}_mean"] = np.nanmean(X, axis=1)
            F[f"{sig}_slope"] = (X[:, -1] - X[:, -2]) / 0.02   # per unit swing
    return pd.DataFrame(F, index=C.index)


def calibrate_frame(df, X, mm_cols):
    """Minus the participant's level-walk median; mm columns / leg length (mm)."""
    X = X.copy()
    for p, idx in df.groupby("participant_id").groups.items():
        lv = (df.participant_id == p) & (df.is_level == 1) & (df.include_biomech == 1)
        X.loc[idx] = X.loc[idx] - X.loc[lv].median()
        X.loc[idx, mm_cols] = X.loc[idx, mm_cols] / (df.loc[idx, "leg_length_cm"].iloc[0] * 10)
    return X


def lopo_proba(make, X, y, g):
    labels = np.unique(y)
    P = np.zeros((len(y), len(labels)))
    for tr, te in LeaveOneGroupOut().split(X, y, g):
        m = make()
        m.fit(X[tr], y[tr])
        P[te] = m.predict_proba(X[te])
    return labels, P


# ---------------- main ----------------
def main():
    df, feats, units = M.load()
    C = pd.read_csv(CURVES).set_index("crossing_id").reindex(df.crossing_id)
    C.index = df.index
    Xcal = M.calibrate(df, feats, units)
    sets = M.feature_sets(feats)
    sel = ((df.is_level == 0) & (df[M.INCLUDE] == 1)).to_numpy()
    y = df.loc[sel, "height_class"].to_numpy(str)
    g = df.loc[sel, "participant_id"].to_numpy()
    lvl = {"H1": 10, "H2": 20, "H3": 30}
    L = []
    w = L.append

    # single-sensor sets (everything a device on that one segment could compute)
    lead = sets["lead only"]
    sensor = {
        "lead foot IMU": [c for c in lead if c.startswith(("lead_foot_", "lead_zhc_")) or c in
                          ("lead_swing_time", "lead_stance_time", *M.LEAD_GLOBAL)],
        "lead thigh IMU": [c for c in lead if c.startswith("lead_thigh_")],
        "lead shank IMU": [c for c in lead if c.startswith("lead_shank_")],
        "lead foot peak height (1 feature)": ["lead_zhc_peak_foot_h"],
        "lead thigh max flexion (1 feature)": ["lead_thigh_max"],
    }
    models = {"all": sets["all"], "lead only": lead, "trail only": sets["trail only"], **sensor}

    def Xof(cols):
        return Xcal.loc[sel, cols].to_numpy(float)

    preds = {k: M.lopo(M.logreg, Xof(v), y, g) for k, v in models.items()}

    w("# ML follow-up: cueing window, time-resolved prediction, robustness\n")
    w(f"_Generated by `Analysis/ML/python/crossing_ml_followup.py` on {datetime.now():%Y-%m-%d %H:%M}._\n")
    w(f"Same rows and rules as `ml_report.md`: {sel.sum()} obstacle crossings (`{M.INCLUDE}` = 1), 10 participants, "
      f"leave-one-participant-out, calibrated features, L2 logistic regression (C = {M.C_LOGREG}). Height = H1/H2/H3, chance 33%. "
      f"95% CIs = participant bootstrap ({N_BOOT} resamples of the 10 participants, LOPO predictions fixed).\n")

    # ---------- 1. cueing window ----------
    d = df.loc[sel]
    win = pd.DataFrame({
        "lead toe-off -> trail toe-off": d.trail_toeoff_t - d.lead_toeoff_t,
        "lead foot apex -> trail toe-off": d.trail_toeoff_t - d.lead_crossing_t_imu,
        "lead landing -> trail toe-off": d.trail_toeoff_t - d.lead_landing_t,
        "trail toe-off -> trail foot apex": d.trail_crossing_t_imu - d.trail_toeoff_t,
    }) * 1000
    w("## 1. Cueing window (ms)\n")
    w("Positive = the first event happens before the second. Events from the Dot (step-4 toe-off / heel-strike, ZHC foot apex).\n")
    w("| interval | n | median | IQR | % > 0 | H1 median | H2 median | H3 median |\n|---|---|---|---|---|---|---|---|")
    for c in win:
        v = win[c].dropna()
        hm = [win.loc[d.height_class == h, c].median() for h in ("H1", "H2", "H3")]
        w(f"| {c} | {len(v)} | {v.median():.0f} | {v.quantile(.25):.0f} to {v.quantile(.75):.0f} | {100*(v > 0).mean():.0f}% | "
          + " | ".join(f"{x:.0f}" for x in hm) + " |")
    pw = win.groupby(d.participant_id)["lead landing -> trail toe-off"].median()
    w("\nPer participant median, lead landing -> trail toe-off (ms): " + ", ".join(f"{p}: {v:.0f}" for p, v in pw.items()) + ".\n")

    # ---------- 2. time-resolved ----------
    mm_sig = ("zhc_h", "zhc_x")
    tr_rows = []
    ref_time = (d.trail_toeoff_t).to_numpy()
    for cut in CUTS:
        F = cut_features(C, cut)
        F = pd.concat([F, df[PRE_SWING]], axis=1)
        mm = [c for c in F.columns if c.startswith(mm_sig)] + ["stride_len_app1", "stride_len_app2"]
        Fc = calibrate_frame(df, F, mm)
        X = Fc.loc[sel].to_numpy(float)
        pred = M.lopo(M.logreg, X, y, g)
        ba = balanced_accuracy_score(y, pred)
        lo, hi = boot_ci(y, pred, g)
        t_cut = (d.lead_toeoff_t + cut / 100 * d.lead_swing_time).to_numpy()
        tr_rows.append({"cut": cut, "n_feat": X.shape[1], "bal_acc": ba, "lo": lo, "hi": hi,
                        "ms_before_trail_toeoff": np.nanmedian((ref_time - t_cut) * 1000)})
    pre = df.loc[sel, PRE_SWING]
    Xp = calibrate_frame(df, df[PRE_SWING], ["stride_len_app1", "stride_len_app2"]).loc[sel].to_numpy(float)
    pp = M.lopo(M.logreg, Xp, y, g)
    pre_ba, pre_ci = balanced_accuracy_score(y, pp), boot_ci(y, pp, g)
    TR = pd.DataFrame(tr_rows)
    apex_pct = d.lead_zhc_peak_h_t.median()
    w("## 2. Time-resolved prediction (lead limb only)\n")
    w(f"Features = the approach strides ({', '.join(PRE_SWING)}) plus, for each lead swing curve (thigh, shank, foot tilt, foot |acc|, "
      "ZHC height and progression), its value at the cut and its max / min / mean / slope from toe-off to the cut. "
      f"Calibrated the same way (level-walk median, lengths / leg length). Median lead foot apex = {apex_pct:.0f}% of the lead swing.\n")
    w(f"Approach strides only (before the lead foot leaves the floor): {pre_ba*100:.1f}% (95% CI {pre_ci[0]*100:.0f}-{pre_ci[1]*100:.0f}).\n")
    w("| data up to (% lead swing) | median time before trail toe-off (ms) | n features | bal. acc | 95% CI |\n|---|---|---|---|---|")
    for _, r in TR.iterrows():
        w(f"| {r.cut:.0f}% | {r.ms_before_trail_toeoff:.0f} | {r.n_feat:.0f} | {r.bal_acc*100:.1f}% | {r.lo*100:.0f}-{r.hi*100:.0f} |")
    w("")

    # ---------- 3. bootstrap CIs ----------
    w("## 3. Bootstrap confidence intervals (height)\n")
    w("| model | n features | bal. acc | 95% CI | minus `all`: 95% CI of the difference |\n|---|---|---|---|---|")
    ci_rows = []
    for k, v in models.items():
        ba = balanced_accuracy_score(y, preds[k])
        if k == "all":
            lo, hi = boot_ci(y, preds[k], g)
            dd = "-"
        else:
            lo, hi, dlo, dhi = boot_ci(y, preds[k], g, other=preds["all"])
            dd = f"{dlo*100:+.0f} to {dhi*100:+.0f} points"
        ci_rows.append((k, ba, lo, hi))
        w(f"| {k} | {len(v)} | {ba*100:.1f}% | {lo*100:.0f}-{hi*100:.0f} | {dd} |")
    lo, hi, dlo, dhi = boot_ci(y, preds["lead foot peak height (1 feature)"], g, other=preds["lead only"])
    w(f"\nOne feature (lead foot peak height) minus lead only: {dlo*100:+.0f} to {dhi*100:+.0f} points (95% CI).")
    pc = {p: np.mean(preds["lead only"][g == p] == y[g == p]) - np.mean(preds["all"][g == p] == y[g == p]) for p in np.unique(g)}
    w("Lead only minus all, per participant (accuracy points): " + ", ".join(f"{p}: {v*100:+.0f}" for p, v in pc.items())
      + f". Better in {sum(v > 0 for v in pc.values())} of 10; mean without 108: {np.mean([v for p, v in pc.items() if p != 108])*100:+.1f}.\n")
    yw = df.loc[sel, "width_class"].to_numpy(str)
    pw_ = M.lopo(M.logreg, Xof(sets["all"]), yw, g)
    lo, hi = boot_ci(yw, pw_, g)
    w(f"Width (all features): {balanced_accuracy_score(yw, pw_)*100:.1f}% (95% CI {lo*100:.0f}-{hi*100:.0f}; chance 50%).\n")

    # ---------- 4. learning curve ----------
    lc_models = ["all", "lead only", "lead foot IMU", "lead foot peak height (1 feature)"]
    P_ = np.unique(g)

    def lc_one(name, n, rep):
        rng = np.random.default_rng(1000 * n + rep)
        X = Xof(models[name])
        pred = np.empty_like(y)
        for p in P_:
            others = [q for q in P_ if q != p]
            tr = np.isin(g, rng.choice(others, n, replace=False))
            te = g == p
            m = M.logreg()
            m.fit(X[tr], y[tr])
            pred[te] = m.predict(X[te])
        return name, n, balanced_accuracy_score(y, pred)

    jobs = [(nm, n, r) for nm in lc_models for n in range(2, 10) for r in range(LC_REPEATS if n < 9 else 1)]
    LC = pd.DataFrame(Parallel(n_jobs=-1)(delayed(lc_one)(*j) for j in jobs), columns=["model", "n_train", "bal_acc"])
    S = LC.groupby(["model", "n_train"]).bal_acc.agg(["mean", lambda s: s.quantile(.1), lambda s: s.quantile(.9)])
    S.columns = ["mean", "p10", "p90"]
    w("## 4. Learning curve (height)\n")
    w(f"Each unseen participant is predicted by a model trained on n randomly chosen other participants ({LC_REPEATS} draws per n; n = 9 = the full LOPO). "
      "Mean balanced accuracy (10th-90th percentile over draws).\n")
    w("| model | " + " | ".join(f"n={n}" for n in range(2, 10)) + " |\n|---|" + "---|" * 8)
    for nm in lc_models:
        w(f"| {nm} | " + " | ".join(f"{S.loc[(nm, n), 'mean']*100:.0f}% ({S.loc[(nm, n), 'p10']*100:.0f}-{S.loc[(nm, n), 'p90']*100:.0f})"
                                   if n < 9 else f"{S.loc[(nm, n), 'mean']*100:.0f}%" for n in range(2, 10)) + " |")
    gain = {nm: (S.loc[(nm, 9), "mean"] - S.loc[(nm, 6), "mean"]) * 100 for nm in lc_models}
    w("\nGain from 6 to 9 training participants (points): " + ", ".join(f"{k}: {v:+.1f}" for k, v in gain.items()) + ".\n")

    # ---------- 5. ordinal model + confidence ----------
    w("## 5. Ordinal model and confidence (height)\n")
    w("Frank & Hall ordinal logistic: two binary models, P(height > H1) and P(height > H2), fitted inside each training set; "
      "P(H1) = 1 - P(>H1), P(H2) = P(>H1) - P(>H2), P(H3) = P(>H2). Error expressed in % of leg length (H1/H2/H3 = 10/20/30%). "
      "Expected height = sum P x level.\n")
    w("| model | features | bal. acc | 95% CI | H1<->H3 errors | MAE of class (% LL) | MAE of expected height (% LL) |\n|---|---|---|---|---|---|---|")
    yl = np.array([lvl[v] for v in y])
    conf_rows = []
    for nm in ("lead only", "all", "lead foot peak height (1 feature)"):
        X = Xof(models[nm])
        lab, Pm = lopo_proba(M.logreg, X, y, g)                               # nominal
        b1 = (yl > 10).astype(int)
        b2 = (yl > 20).astype(int)
        _, P1 = lopo_proba(lambda: M.logreg(), X, b1.astype(str), g)
        _, P2 = lopo_proba(lambda: M.logreg(), X, b2.astype(str), g)
        p1, p2 = P1[:, 1], np.minimum(P2[:, 1], P1[:, 1])
        Po = np.column_stack([1 - p1, p1 - p2, p2])
        for kind, Pk in (("nominal", Pm), ("ordinal", Po)):
            pred = lab[np.argmax(Pk, axis=1)]
            pl = np.array([lvl[v] for v in pred])
            exp_h = Pk @ np.array([10, 20, 30])
            lo, hi = boot_ci(y, pred, g)
            far = int(np.sum(np.abs(pl - yl) == 20))
            w(f"| {kind} | {nm} | {balanced_accuracy_score(y, pred)*100:.1f}% | {lo*100:.0f}-{hi*100:.0f} | {far} | "
              f"{np.mean(np.abs(pl - yl)):.1f} | {np.mean(np.abs(exp_h - yl)):.1f} |")
            if kind == "nominal":
                conf_rows.append((nm, Pk, pred))
    w("\nConfidence (nominal model): accuracy on the crossings where the top class probability >= threshold, and the share of crossings kept.\n")
    w("| model | >= 0.4 | >= 0.5 | >= 0.6 | >= 0.7 |\n|---|---|---|---|---|")
    for nm, Pk, pred in conf_rows:
        cells = []
        for th in (0.4, 0.5, 0.6, 0.7):
            k = Pk.max(axis=1) >= th
            cells.append(f"{np.mean(pred[k] == y[k])*100:.0f}% acc, {k.mean()*100:.0f}% kept" if k.any() else "-")
        w(f"| {nm} | " + " | ".join(cells) + " |")
    w("\nFigures: `fig_cueing_time.png`, `fig_learning_curve.png`.\n")
    (M.OUT / "ml_followup.md").write_text("\n".join(L), encoding="utf-8")
    fig_time(TR, d, pre_ba, ci_rows)
    fig_lc(S, lc_models)
    print("wrote", M.OUT / "ml_followup.md")


# ---------------- figures ----------------
def fig_time(TR, d, pre_ba, ci_rows):
    fig, ax = plt.subplots(figsize=(8.5, 4.2), facecolor=M.SURFACE)
    x = -TR.ms_before_trail_toeoff
    ax.fill_between(x, TR.lo * 100, TR.hi * 100, color=M.BLUE, alpha=0.15, lw=0)
    ax.plot(x, TR.bal_acc * 100, color=M.BLUE, lw=2, marker="o", ms=5, mec=M.SURFACE, mew=1.5)
    for _, r in TR.iloc[[0, 5, 10]].iterrows():
        ax.annotate(f"{r.cut:.0f}% lead swing", (-r.ms_before_trail_toeoff, r.bal_acc * 100), xytext=(0, 10),
                    textcoords="offset points", ha="center", fontsize=8, color=M.INK2)
    ev = {"lead foot apex": -np.nanmedian((d.trail_toeoff_t - d.lead_crossing_t_imu) * 1000),
          "lead landing": -np.nanmedian((d.trail_toeoff_t - d.lead_landing_t) * 1000),
          "trail toe-off": 0}
    for k, v in ev.items():
        ax.axvline(v, color=M.INK2, lw=1, ls=":")
        ax.text(v, 97, k, rotation=90, va="top", ha="right", fontsize=8, color=M.INK2)
    ax.axhline(100 / 3, color=M.INK2, ls="--", lw=1)
    ax.text(ax.get_xlim()[0], 100 / 3 + 1, " chance", fontsize=8, color=M.INK2, va="bottom")
    ax.set_ylim(20, 100)
    ax.set_xlabel("time relative to the trailing foot's toe-off (ms, median)", color=M.INK2, fontsize=9)
    ax.set_ylabel("balanced accuracy, unseen participant (%)", color=M.INK2, fontsize=9)
    ax.set_title("Height from lead-limb data available so far (band = 95% participant bootstrap CI)", fontsize=10, color=M.INK, loc="left")
    M.style(ax)
    ax.yaxis.grid(True, color=M.GRID, lw=0.8)
    ax.xaxis.grid(False)
    fig.tight_layout()
    fig.savefig(M.OUT / "fig_cueing_time.png", dpi=200, facecolor=M.SURFACE)
    plt.close(fig)


def fig_lc(S, names):
    fig, ax = plt.subplots(figsize=(8, 4), facecolor=M.SURFACE)
    n = np.arange(2, 10)
    ends = sorted(((S.loc[(nm, 9), "mean"] * 100, nm) for nm in names))
    ylab, last = {}, -np.inf
    for v, nm in ends:                       # direct labels at least 2.8 points apart
        last = max(v, last + 2.8)
        ylab[nm] = last
    for nm, col in zip(names, PALETTE):
        m = np.array([S.loc[(nm, k), "mean"] for k in n]) * 100
        lo = np.array([S.loc[(nm, k), "p10"] for k in n]) * 100
        hi = np.array([S.loc[(nm, k), "p90"] for k in n]) * 100
        ax.fill_between(n, lo, hi, color=col, alpha=0.10, lw=0)
        ax.plot(n, m, color=col, lw=2, marker="o", ms=5, mec=M.SURFACE, mew=1.5, label=nm)
        ax.text(9.12, ylab[nm], nm, color=M.INK2, fontsize=8, va="center")
    ax.axhline(100 / 3, color=M.INK2, ls="--", lw=1)
    ax.set_xlim(1.8, 11.2)
    ax.set_xticks(n)
    ax.set_ylim(20, 80)
    ax.set_xlabel("number of training participants", color=M.INK2, fontsize=9)
    ax.set_ylabel("balanced accuracy, unseen participant (%)", color=M.INK2, fontsize=9)
    ax.set_title("Learning curve, height (band = 10th-90th percentile over random training sets; chance dashed)",
                 fontsize=9.5, color=M.INK, loc="left")
    M.style(ax)
    ax.yaxis.grid(True, color=M.GRID, lw=0.8)
    ax.xaxis.grid(False)
    ax.legend(frameon=False, fontsize=8, labelcolor=M.INK2, loc="lower left", ncol=2)
    fig.tight_layout()
    fig.savefig(M.OUT / "fig_learning_curve.png", dpi=200, facecolor=M.SURFACE)
    plt.close(fig)


if __name__ == "__main__":
    main()
