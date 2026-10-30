"""Leave-one-participant-out (LOPO) feasibility models for the obstacle-crossing dataset.

Question: do the wearable (Dot) features ALONE carry information about the obstacle,
in a participant the model has never seen?
  Q1  obstacle height class (H1/H2/H3) from all Dot features
  Q2  which segment (thigh / shank / foot angles, foot acceleration, ZHC trajectory,
      spatiotemporal) and which limb carries it (feature-group runs)
  Q3  is the leading limb alone enough (lead-only features; nothing timed by the trail limb)
  Q3b how few features are needed (SelectKBest inside each training fold)
  Q4  obstacle width (W1/W2)

Rules (so that "unseen participant" holds):
  * input = columns the data dictionary marks FEATURE (Dot only); never LABEL / META /
    REFERENCE / TARGET / FLAG; `*_zhc_peak_toe_h` left out (provisional geometry);
  * every fitted step (imputation, scaling, feature selection, model) is fitted on the
    9 training participants only;
  * main model = L2 logistic regression with C fixed a priori (no tuning), so the
    permutation test repeats exactly the same procedure; random forest = check;
  * "calibrated" features = minus the participant's own level-walk median, lengths (mm)
    divided by leg length (a short normal-walking calibration a device could do);
  * significance = permutation test, labels shuffled WITHIN each participant.

Reads  Results/ML Dataset/Crossing_Master_YoungAdults.csv + data_dictionary.md
Writes Results/ML Models/  ml_results.csv, ml_report.md, 3 PNG figures.
No statistics on the biomechanics themselves; this is a feasibility check (n = 10).
"""
from __future__ import annotations

import re
import warnings
from datetime import datetime
from pathlib import Path

import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
import numpy as np
import pandas as pd
from joblib import Parallel, delayed
from sklearn.ensemble import RandomForestClassifier
from sklearn.feature_selection import SelectKBest, f_classif
from sklearn.impute import SimpleImputer
from sklearn.linear_model import LogisticRegression
from sklearn.metrics import balanced_accuracy_score, confusion_matrix, f1_score
from sklearn.model_selection import LeaveOneGroupOut
from sklearn.pipeline import make_pipeline
from sklearn.preprocessing import StandardScaler

warnings.filterwarnings("ignore", category=RuntimeWarning)   # f_classif on constant (all-missing) columns
ROOT = Path(__file__).resolve().parents[3]
DATA = ROOT / "Results" / "ML Dataset" / "Crossing_Master_YoungAdults.csv"
DICT = ROOT / "Results" / "ML Dataset" / "data_dictionary.md"
OUT = ROOT / "Results" / "ML Models"

# ---------------- config ----------------
C_LOGREG = 0.1            # fixed a priori (strong L2 for ~230 rows x ~100 features)
N_PERM_MAIN = 1000        # permutations for the headline runs
N_PERM_GROUP = 300        # permutations for the feature-group runs
K_SPARSE = [1, 3, 5, 10]
SEED = 0
INCLUDE = "include_ml"    # row filter; sensitivity run uses include_ml_noflag
LEAD_GLOBAL = ["stride_len_app1", "stride_len_app2", "speed_approach", "speed_cross", "cadence"]
TRAIL_TIMED = ["cross_duration"]          # needs the trail landing -> never in lead-only
GROUPS = {                                # segment / signal groups (regex on the name)
    "thigh": r"_thigh_",
    "shank": r"_shank_",
    "foot angle": r"_foot_(?!acc)",
    "foot acc": r"_foot_acc_",
    "ZHC trajectory": r"_zhc_",
    "spatiotemporal": r"swing_time|stance_time|stride_len|speed|cadence|cross_duration",
}
# light-mode palette (dataviz reference instance)
BLUE, ORANGE, AQUA = "#2a78d6", "#eb6834", "#1baf7a"
INK, INK2, GRID, SURFACE = "#0b0b0b", "#52514e", "#e4e3df", "#fcfcfb"


# ---------------- data ----------------
def load():
    df = pd.read_csv(DATA)
    spec = {}
    for ln in DICT.read_text(encoding="utf-8").splitlines():
        m = re.match(r"^\| \d+ \| `([^`]+)` \| ([^|]+) \| ([^|]+) \|", ln)
        if m:
            spec[m.group(1)] = (m.group(2).strip(), m.group(3).strip())
    feats = [c for c, (role, _) in spec.items()
             if role == "FEATURE" and c in df and df[c].notna().any() and not c.endswith("_zhc_peak_toe_h")]
    units = {c: spec[c][1] for c in feats}
    return df, feats, units


def calibrate(df, feats, units):
    """Per participant: minus own level-walk median; mm columns divided by leg length (mm)."""
    X = df[feats].copy()
    for p, idx in df.groupby("participant_id").groups.items():
        lv = (df.participant_id == p) & (df.is_level == 1) & (df.include_biomech == 1)
        base = df.loc[lv, feats].median()
        X.loc[idx] = X.loc[idx] - base
        ll = df.loc[idx, "leg_length_cm"].iloc[0] * 10
        mm = [c for c in feats if units[c] == "mm"]
        X.loc[idx, mm] = X.loc[idx, mm] / ll
    return X


def feature_sets(feats):
    lead = [c for c in feats if c.startswith("lead_") or c in LEAD_GLOBAL]
    trail = [c for c in feats if c.startswith("trail_")]
    sets = {"all": feats, "lead only": lead, "trail only": trail}
    for g, rx in GROUPS.items():
        cols = [c for c in feats if re.search(rx, c)]
        sets[f"{g}"] = cols
        sets[f"{g} (lead)"] = [c for c in cols if c in lead]
        sets[f"{g} (trail)"] = [c for c in cols if c in trail]
    return {k: v for k, v in sets.items() if v}


# ---------------- models ----------------
def logreg(k=None):
    steps = [SimpleImputer(strategy="median", keep_empty_features=True), StandardScaler()]
    if k:
        steps.append(SelectKBest(f_classif, k=k))
    steps.append(LogisticRegression(C=C_LOGREG, max_iter=5000))
    return make_pipeline(*steps)


def forest():
    return make_pipeline(SimpleImputer(strategy="median", keep_empty_features=True),
                         RandomForestClassifier(n_estimators=500, min_samples_leaf=2, class_weight="balanced",
                                                random_state=SEED, n_jobs=-1))


def lopo(make, X, y, g, keep_selected=False):
    pred = np.empty_like(y)
    sel = []
    for tr, te in LeaveOneGroupOut().split(X, y, g):
        m = make()
        m.fit(X[tr], y[tr])
        pred[te] = m.predict(X[te])
        if keep_selected:
            sel.append(m.named_steps["selectkbest"].get_support())
    return (pred, sel) if keep_selected else pred


def shuffle_within(y, g, rng):
    yp = y.copy()
    for p in np.unique(g):
        i = np.where(g == p)[0]
        yp[i] = yp[rng.permutation(i)]
    return yp


def perm_null(make, X, y, g, n):
    def one(seed):
        yp = shuffle_within(y, g, np.random.default_rng(seed))
        return balanced_accuracy_score(yp, lopo(make, X, yp, g))
    return np.array(Parallel(n_jobs=-1)(delayed(one)(SEED + 1 + s) for s in range(n)))


def score(y, pred, g):
    per = {f"acc_{p}": float(np.mean(pred[g == p] == y[g == p])) for p in np.unique(g)}
    return {"bal_acc": balanced_accuracy_score(y, pred), "macro_f1": f1_score(y, pred, average="macro"), **per}


# ---------------- main ----------------
def main():
    OUT.mkdir(parents=True, exist_ok=True)
    df, feats, units = load()
    Xcal = calibrate(df, feats, units)
    sets = feature_sets(feats)
    tasks = {"height": "height_class", "width": "width_class"}
    rows, conf, sparse, null_band = [], {}, [], {}

    def run(task, set_name, norm, model, include=INCLUDE, n_perm=0):
        sel = (df.is_level == 0) & (df[include] == 1)
        cols = sets[set_name]
        X = (Xcal if norm == "calibrated" else df[feats]).loc[sel, cols].to_numpy(float)
        y = df.loc[sel, tasks[task]].to_numpy(str)
        g = df.loc[sel, "participant_id"].to_numpy()
        make = logreg if model == "logreg" else forest
        pred = lopo(make, X, y, g)
        r = {"task": task, "features": set_name, "normalization": norm, "model": model, "rows": include,
             "n_features": len(cols), "n_rows": len(y), "n_participants": len(np.unique(g)),
             "chance": 1 / len(np.unique(y)), **score(y, pred, g)}
        if n_perm:
            null = perm_null(make, X, y, g, n_perm)
            r["perm_p"] = (1 + np.sum(null >= r["bal_acc"])) / (1 + n_perm)
            r["null_mean"], r["null_95"] = float(null.mean()), float(np.percentile(null, 95))
            r["n_perm"] = n_perm
            null_band[(task, set_name)] = r["null_95"]
        rows.append(r)
        if include == INCLUDE:
            labels = np.unique(y)
            conf[(task, set_name, norm, model)] = (labels, confusion_matrix(y, pred, labels=labels))
        print(f"{task:6s} {set_name:24s} {norm:10s} {model:6s} bal_acc={r['bal_acc']:.3f}"
              + (f"  p={r['perm_p']:.4f}" if n_perm else ""), flush=True)

    for task in tasks:
        for s in sets:
            main_run = s in ("all", "lead only", "trail only")
            run(task, s, "calibrated", "logreg", n_perm=N_PERM_MAIN if main_run else N_PERM_GROUP)
            if main_run:
                run(task, s, "raw", "logreg")
                run(task, s, "calibrated", "forest")
                run(task, s, "raw", "forest")
    run("height", "all", "calibrated", "logreg", include="include_ml_noflag")

    # ---- Q3b: how few features (selection inside each training fold) ----
    for s in ("all", "lead only"):
        sel = (df.is_level == 0) & (df[INCLUDE] == 1)
        cols = sets[s]
        X = Xcal.loc[sel, cols].to_numpy(float)
        y = df.loc[sel, "height_class"].to_numpy(str)
        g = df.loc[sel, "participant_id"].to_numpy()
        for k in K_SPARSE:
            pred, chosen = lopo(lambda: logreg(k), X, y, g, keep_selected=True)
            freq = np.mean(chosen, axis=0)
            top = [(cols[i], freq[i]) for i in np.argsort(-freq)[:max(k, 5)] if freq[i] > 0]
            sparse.append({"features": s, "k": k, "bal_acc": balanced_accuracy_score(y, pred),
                           "top": "; ".join(f"{c} ({f*10:.0f}/10)" for c, f in top)})
            print(f"sparse {s} k={k} bal_acc={sparse[-1]['bal_acc']:.3f}", flush=True)

    R = pd.DataFrame(rows)
    R.to_csv(OUT / "ml_results.csv", index=False, float_format="%.4f")
    figures(R, conf, null_band)
    report(R, pd.DataFrame(sparse), conf, df, feats)
    print(f"wrote {OUT}")


# ---------------- figures ----------------
def style(ax):
    ax.set_facecolor(SURFACE)
    for s in ("top", "right"):
        ax.spines[s].set_visible(False)
    for s in ("left", "bottom"):
        ax.spines[s].set_color(GRID)
    ax.tick_params(colors=INK2, labelsize=9)
    ax.xaxis.grid(True, color=GRID, lw=0.8)
    ax.set_axisbelow(True)


def figures(R, conf, band):
    prim = R[(R.normalization == "calibrated") & (R.model == "logreg") & (R.rows == INCLUDE)]
    # 1. balanced accuracy by feature set, height and width side by side
    order = list(dict.fromkeys(prim.features))
    fig, axes = plt.subplots(1, 2, figsize=(11, 0.32 * len(order) + 1.6), sharey=True, facecolor=SURFACE)
    for ax, task in zip(axes, ("height", "width")):
        d = prim[prim.task == task].set_index("features").reindex(order)
        yy = np.arange(len(order))[::-1]
        ax.barh(yy, d.bal_acc * 100, height=0.62, color=BLUE, edgecolor=SURFACE, lw=2)
        for yi, (nm, v) in zip(yy, d.bal_acc.items()):
            b95 = band.get((task, nm), np.nan) * 100
            ax.plot([b95] * 2, [yi - 0.36, yi + 0.36], color=INK, lw=1.5)
            ax.text(np.nanmax([v * 100, b95]) + 1.2, yi, f"{v*100:.0f}", va="center", fontsize=8, color=INK2)
        ax.axvline(d.chance.iloc[0] * 100, color=INK2, ls="--", lw=1)
        ax.set_yticks(yy, order)
        ax.set_xlim(0, 100)
        ax.set_xlabel("balanced accuracy, unseen participant (%)", color=INK2, fontsize=9)
        ax.set_title(f"{task}  (chance {d.chance.iloc[0]*100:.0f}% dashed; black tick = permutation 95th pct)",
                     fontsize=9.5, color=INK, loc="left")
        style(ax)
    fig.tight_layout()
    fig.savefig(OUT / "fig_feature_sets.png", dpi=200, facecolor=SURFACE)
    plt.close(fig)

    # 2. confusion matrices (row %)
    keys = [("height", "all"), ("height", "lead only"), ("width", "all")]
    fig, axes = plt.subplots(1, 3, figsize=(11, 3.6), facecolor=SURFACE)
    cmap = matplotlib.colors.LinearSegmentedColormap.from_list("blue", ["#f0f5fc", "#86b6ef", "#2a78d6", "#104281"])
    for ax, (task, s) in zip(axes, keys):
        lab, cm = conf[(task, s, "calibrated", "logreg")]
        pc = cm / cm.sum(axis=1, keepdims=True) * 100
        ax.imshow(pc, cmap=cmap, vmin=0, vmax=100)
        for i in range(len(lab)):
            for j in range(len(lab)):
                ax.text(j, i, f"{pc[i, j]:.0f}%\n(n={cm[i, j]})", ha="center", va="center", fontsize=8.5,
                        color="white" if pc[i, j] > 55 else INK)
        ax.set_xticks(range(len(lab)), lab)
        ax.set_yticks(range(len(lab)), lab)
        ax.set_xlabel("predicted", color=INK2, fontsize=9)
        ax.set_ylabel("true", color=INK2, fontsize=9)
        ax.set_title(f"{task} - {s}", fontsize=10, color=INK, loc="left")
        ax.tick_params(colors=INK2, labelsize=9)
        for sp in ax.spines.values():
            sp.set_visible(False)
    fig.tight_layout()
    fig.savefig(OUT / "fig_confusion.png", dpi=200, facecolor=SURFACE)
    plt.close(fig)

    # 3. per-participant accuracy, height (all / lead / trail)
    d = prim[(prim.task == "height") & prim.features.isin(["all", "lead only", "trail only"])].set_index("features")
    pcols = [c for c in R.columns if c.startswith("acc_")]
    fig, ax = plt.subplots(figsize=(8, 3.6), facecolor=SURFACE)
    xx = np.arange(len(pcols))
    for (nm, col, dx) in (("all", BLUE, -0.18), ("lead only", ORANGE, 0), ("trail only", AQUA, 0.18)):
        ax.scatter(xx + dx, d.loc[nm, pcols].astype(float) * 100, s=42, color=col, edgecolor=SURFACE, lw=1.5,
                   label=nm, zorder=3)
    ax.axhline(100 / 3, color=INK2, ls="--", lw=1)
    ax.set_xticks(xx, [c[4:] for c in pcols])
    ax.set_ylim(0, 105)
    ax.set_ylabel("accuracy when held out (%)", color=INK2, fontsize=9)
    ax.set_xlabel("participant", color=INK2, fontsize=9)
    ax.set_title("Height class, each participant tested unseen (chance 33% dashed)", fontsize=10, color=INK, loc="left")
    ax.yaxis.grid(True, color=GRID, lw=0.8)
    ax.xaxis.grid(False)
    style(ax)
    ax.xaxis.grid(False)
    ax.legend(frameon=False, fontsize=9, labelcolor=INK2, loc="lower right", ncol=3)
    fig.tight_layout()
    fig.savefig(OUT / "fig_participants.png", dpi=200, facecolor=SURFACE)
    plt.close(fig)


# ---------------- report ----------------
def fmt_p(p):
    return "-" if pd.isna(p) else ("< 0.001" if p < 0.001 else f"{p:.3f}")


def report(R, S, conf, df, feats):
    L = []
    w = L.append
    sel = (df.is_level == 0) & (df[INCLUDE] == 1)
    w("# ML feasibility: can Dot features alone tell the obstacle?\n")
    w(f"_Generated by `Analysis/ML/python/crossing_ml.py` on {datetime.now():%Y-%m-%d %H:%M}._\n")
    w("## Setup\n")
    w(f"- **Rows:** obstacle crossings with `{INCLUDE}` = 1: {sel.sum()} rows from {df.loc[sel,'participant_id'].nunique()} participants "
      f"(H1/H2/H3 = {', '.join(str(int((df.loc[sel,'height_class']==h).sum())) for h in ['H1','H2','H3'])}; "
      f"W1/W2 = {', '.join(str(int((df.loc[sel,'width_class']==x).sum())) for x in ['W1','W2'])}).")
    w(f"- **Inputs:** the {len(feats)} Dot FEATURE columns (thigh/shank/foot angles and angular velocity, foot acceleration, ZHC foot "
      "trajectory, spatiotemporal). No labels, camera, timing/block or flag columns; toe height left out (provisional).")
    w("- **Test:** leave-one-participant-out: train on 9, test on the unseen 10th, 10 times. Imputation (median), scaling, feature "
      "selection and the model are fitted on the 9 training participants only.")
    w(f"- **Main model:** L2 logistic regression, C = {C_LOGREG} fixed in advance. Check: random forest (500 trees).")
    w("- **Calibrated features:** minus the participant's own level-walk median; lengths in mm divided by leg length. "
      "Raw = the dataset values.")
    w(f"- **Significance:** permutation test, labels shuffled within each participant ({N_PERM_MAIN} permutations for "
      f"all / lead / trail, {N_PERM_GROUP} for the feature groups); p = (1 + #null >= observed) / (1 + n).")
    w("- **Caveat:** lead/trail roles and the crossing stride come from the camera (Dot-only detection agreed on all matched "
      "crossings, 90% found), so the model assumes the crossing is already located.\n")

    def tab(d, extra=True):
        hdr = "| task | features | norm | model | n feat | n rows | bal. acc | macro F1 | chance |" + (" perm p | null 95% |" if extra else "")
        w(hdr)
        w("|" + "---|" * (hdr.count("|") - 1))
        for _, r in d.iterrows():
            s = (f"| {r.task} | {r.features} | {r.normalization} | {r.model} | {r.n_features} | {r.n_rows} | "
                 f"{r.bal_acc*100:.1f}% | {r.macro_f1:.2f} | {r.chance*100:.0f}% |")
            if extra:
                s += f" {fmt_p(r.get('perm_p'))} | {'-' if pd.isna(r.get('null_95')) else f'{r.null_95*100:.1f}%'} |"
            w(s)
        w("")

    main_sets = ["all", "lead only", "trail only"]
    w("## Q1 / Q3 / Q4. Headline runs\n")
    tab(R[R.features.isin(main_sets) & (R.rows == INCLUDE)])
    w("Sensitivity (drift flag ignored, `include_ml_noflag`):\n")
    tab(R[R.rows != INCLUDE])
    w("## Q2. Which segment and limb (calibrated logistic regression)\n")
    for task in ("height", "width"):
        tab(R[(R.task == task) & ~R.features.isin(main_sets) & (R.rows == INCLUDE)])
    w("## Q3b. How few features (height, calibrated, SelectKBest inside each training fold)\n")
    w("| features | k | bal. acc | most often selected (folds of 10) |\n|---|---|---|---|")
    for _, r in S.iterrows():
        w(f"| {r.features} | {r.k} | {r.bal_acc*100:.1f}% | {r.top} |")
    w("\n## Per participant (height, calibrated logistic regression)\n")
    pc = [c for c in R.columns if c.startswith("acc_")]
    w("| features | " + " | ".join(c[4:] for c in pc) + " |\n|---|" + "---|" * len(pc))
    for s in main_sets:
        r = R[(R.task == "height") & (R.features == s) & (R.normalization == "calibrated") & (R.model == "logreg") & (R.rows == INCLUDE)].iloc[0]
        w(f"| {s} | " + " | ".join(f"{r[c]*100:.0f}%" for c in pc) + " |")
    w("\n## Confusion matrices (calibrated logistic regression, counts; rows = true)\n")
    for key in [("height", "all"), ("height", "lead only"), ("width", "all")]:
        lab, cm = conf[(key[0], key[1], "calibrated", "logreg")]
        w(f"**{key[0]} - {key[1]}**\n\n| true \\ pred | " + " | ".join(lab) + " |\n|---|" + "---|" * len(lab))
        for i, l in enumerate(lab):
            w(f"| {l} | " + " | ".join(str(v) for v in cm[i]) + " |")
        w("")
    w("Figures: `fig_feature_sets.png`, `fig_confusion.png`, `fig_participants.png`. All numbers: `ml_results.csv`.\n")
    (OUT / "ml_report.md").write_text("\n".join(L), encoding="utf-8")


if __name__ == "__main__":
    main()
