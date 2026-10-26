clc; clear; close all;
addpath(fileparts(mfilename('fullpath')));
%% ========================================================================
%% STEP 9 - GROUP CROSSING ANALYSIS  (Tier 1 + Tier 2, ACROSS participants)
%% ========================================================================
% The pipeline capstone: run ONCE after steps 1-8 are complete for every
% participant (it reads many tests, not one). Set TESTS below to the cohort.
% Aggregates the per-participant step-8 / step-7 / step-4 outputs into GROUP
% results (mean +/- SD ACROSS participants) for the obstacle-crossing study.
% Two-level average: per participant, mean per condition first; then mean +/- SD
% over participants (so everyone weighs equally, regardless of # crossings).
%
% Reads, per test (= participant):
%   CrossingParams_TestN.mat       -> clearance (toe/heel), min clearance (from
%                                     the stored arc), foot placement (lift/land)
%   SegmentedParams_TestN.mat      -> joint strides (ROM = max-min) + ZHC windows
%   SegTrajectories_WithCamera_*   -> per-stride terrain/role labels (camera)
%
% Conditions: terrain W{1,2}_H{1,2,3} x role {Leading, Trailing}; Level_Walk is
% the ROM baseline. NO normalization (absolute units: cm for lengths, deg for ROM).
%
% Output -> Results/Group Analysis/  (overwrites; cohort in the filename, n inside)
%   GroupCrossing_<COHORT>_Summary.xlsx   (Tier1 + ROM sheets, mean/SD/n)
%   GroupCrossing_<COHORT>.mat            (aggregated struct, for re-plotting/stats)
%   Figures/Group_Tier1.png, Group_ROM.png

%% ===================== CONFIG =====================
TESTS    = [101 102 103 104 105 106 107 108 109];  % participant test numbers (Subject ID = Test #)
COHORT   = 'YoungAdults';
TERRAINS = {'W1_H1','W1_H2','W1_H3','W2_H1','W2_H2','W2_H3'};
ROLES    = {'Leading','Trailing'};
JOINTS   = {'hip_flexion','knee_angle','ankle_angle'};   % Tier-2 joint ROM (deg), L/R pooled by role
SEGMENTS = {'Foot','Shank','Thigh'};                     % Tier-2 IMU SEGMENT tilt ROM (deg), Dot reference
SEG_SYS  = 'Dot';                                        % which IMU system for the segment ROM

%% -------------------- PER-PARTICIPANT CLEANING (group-analysis only) --------------------
% Targeted ROM cleaning for a participant with a KNOWN mid-trial artifact. Applies
% ONLY to the listed test and ONLY to the listed ROM signals - every other
% participant, Tier-1, and the per-test pipeline (steps 1-8) are untouched.
%   (a) MAD gate + median: drop strides > madK*MAD from this participant/condition
%       median, then aggregate with the median (robust to the jump).
%   (b) exclusion: drop whole condition codes and/or time windows (s) for that test.
% Test 106: a mid-trial thigh-IMU disturbance inflated hip/thigh (and knee) ROM,
% worst on obstacle codes 11 / 13 / 23 (W1_H1, W1_H3, W2_H3).
CLEAN = struct('test',{},'signals',{},'madK',{},'excludeCodes',{},'excludeWin',{});
CLEAN(1).test         = 106;
CLEAN(1).signals      = {'hip_flexion','knee_angle','Thigh'};   % joints + segment affected by the thigh IMU
CLEAN(1).madK         = 3;                                      % (a) drop > 3*MAD from the per-condition median
CLEAN(1).excludeCodes = {'W1_H1','W1_H3','W2_H3'};              % (b) drop these conditions entirely for 106
CLEAN(1).excludeWin   = [];                                     % (b) optional [t1 t2; ...] seconds to drop

%% -------------------- SPATIOTEMPORAL + PEAK-TIMING --------------------
STPARAMS = {'stride','cadence','speed'};                        % crossing-stride spatiotemporal
STNICE   = {'Stride length','Cadence','Speed'};
STYLAB   = {'Stride length (cm)','Cadence (steps/min)','Speed (m/s)'};
PKT_JOINTS = {'hip_flexion','knee_angle','ankle_angle'};        % peak-timing signals (% gait cycle)
PKT_SEGS   = {'Foot','Shank','Thigh'};
PKALL  = [PKT_JOINTS, {'FootHeight'}, PKT_SEGS];                 % all peak-timing keys
% Which extremum's timing to report per signal ('max' or 'min'). The definition
% figure shows BOTH - flip any of these to 'min' once you see which is the real peak.
PK_EXTREMUM = struct('hip_flexion','min', 'knee_angle','min', 'ankle_angle','max', ...
                     'FootHeight','max', 'Foot','min', 'Shank','min', 'Thigh','max');

% -------- Named PEAK parameters (whole cycle, referenced to begin-ZVP) ----------
% Reported as a magnitude in the NAMED direction (the sign flip is handled below).
% ext = which extremum ('max'/'min') in THIS data's sign convention. role: P/S/C.
% Flip an ext here if the definition figure shows the other extremum is the event.
% ext: 'min'/'max' = directional extremum (needs a trustworthy sign -> the signal is
% sign-normalized at load, see signNormTools); 'abs' = largest |excursion| from stance
% (SIGN-INVARIANT, for a unidirectional joint). The knee only flexes (extension past
% neutral is negligible), so knee flexion uses 'abs' and needs no sign normalization.
% Ankle is bidirectional (dorsi/plantar) so it IS sign-normalized; its joint magnitudes
% are drift-noisy, so clean/override as for hip. The hip + Dot segments are sign-stable.
PEAKDEF = {
%   key              display                       signal         ext    role
   'hip_pk_flex',   'Hip peak flexion',           'hip_flexion', 'min', 'P';
   'hip_pk_ext',    'Hip peak extension',         'hip_flexion', 'max', 'S';
   'knee_pk_flex',  'Knee peak flexion',          'knee_angle',  'abs', 'P';
   'ank_plant',     'Ankle peak plantarflexion',  'ankle_angle', 'min', 'P';
   'ank_dorsi',     'Ankle peak dorsiflexion',    'ankle_angle', 'max', 'P';
   'thigh_fwd',     'Thigh peak forward tilt',    'Thigh',       'max', 'P';
   'shank_back',    'Shank peak backward (heelup)','Shank',      'min', 'P';
   'foot_toedown',  'Foot peak toe-down',         'Foot',        'min', 'P';
   'thigh_back',    'Thigh peak backward tilt',   'Thigh',       'min', 'S';
   'shank_fwd',     'Shank peak forward (reach)', 'Shank',       'max', 'S';
   'foot_toeup',    'Foot peak toe-up',           'Foot',        'max', 'S';
};
PK_JOINT_SIGS = {'hip_flexion','knee_angle','ankle_angle'};   % joint peaks (vs IMU segments)

%% -------------------- MANUAL OVERRIDES (optional) --------------------
% ONE ROW PER value you want to set by hand. Each row:
%     GROUP , SIGNAL , CONDITION , MEAN , SD
% - GROUP   : 'T1' | 'SPT' | 'ROM' | 'SROM' | 'PKT'
% - SIGNAL  : T1  -> clr_toe, clr_heel, clr_min, lift_dist, land_dist
%             SPT -> stride, cadence, speed
%             ROM -> hip_flexion, knee_angle, ankle_angle
%             SROM-> Foot, Shank, Thigh
%             PKT -> hip_flexion, knee_angle, ankle_angle, FootHeight, Foot, Shank, Thigh
% - CONDITION: one of (exact strings) --
%       W1_H1_Leading  W1_H1_Trailing   W1_H2_Leading  W1_H2_Trailing
%       W1_H3_Leading  W1_H3_Trailing   W2_H1_Leading  W2_H1_Trailing
%       W2_H2_Leading  W2_H2_Trailing   W2_H3_Leading  W2_H3_Trailing
%       Level_Walk   (only for SPT / ROM / SROM / PKT, NOT T1)
% - MEAN / SD: the value in the SHOWN units (T1 & stride = cm, cadence = steps/min,
%              speed = m/s, ROM/segment = deg, peak timing = % GC).  Use NaN to KEEP
%              the computed value for that one (so you can set only the bar or only
%              the error bar). Add as many rows as you like; empty {} = all computed.
% Overrides feed the figures AND the Markdown/xlsx.
% Template: joint-ROM SD for every condition. MEAN stays nan (computed); fill the
% last column (SD, deg) where you want a manual error bar, leave nan to keep computed.
OVERRIDE = {
%    GROUP   SIGNAL          CONDITION          MEAN   SD
     'ROM', 'hip_flexion',  'W1_H1_Leading',    nan,   23  ;
     'ROM', 'hip_flexion',  'W1_H1_Trailing',   nan,   16 ;
     'ROM', 'hip_flexion',  'W1_H2_Leading',    nan,   28  ;
     'ROM', 'hip_flexion',  'W1_H2_Trailing',   nan,   nan ;
     'ROM', 'hip_flexion',  'W1_H3_Leading',    nan,   30  ;
     'ROM', 'hip_flexion',  'W1_H3_Trailing',   nan,   nan ;
     'ROM', 'hip_flexion',  'W2_H1_Leading',    nan,   21  ;
     'ROM', 'hip_flexion',  'W2_H1_Trailing',   nan,   nan ;
     'ROM', 'hip_flexion',  'W2_H2_Leading',    nan,   14 ;
     'ROM', 'hip_flexion',  'W2_H2_Trailing',   nan,   nan ;
     'ROM', 'hip_flexion',  'W2_H3_Leading',    nan,   23 ;
     'ROM', 'hip_flexion',  'W2_H3_Trailing',   nan,   nan ;
     'ROM', 'hip_flexion',  'Level_Walk',       nan,   nan ;
     'ROM', 'knee_angle',   'W1_H1_Leading',    nan,   32 ;
     'ROM', 'knee_angle',   'W1_H1_Trailing',   nan,   nan ;
     'ROM', 'knee_angle',   'W1_H2_Leading',    nan,   37 ;
     'ROM', 'knee_angle',   'W1_H2_Trailing',   nan,   nan ;
     'ROM', 'knee_angle',   'W1_H3_Leading',    nan,   28 ;
     'ROM', 'knee_angle',   'W1_H3_Trailing',   nan,   nan ;
     'ROM', 'knee_angle',   'W2_H1_Leading',    nan,   27 ;
     'ROM', 'knee_angle',   'W2_H1_Trailing',   nan,   nan ;
     'ROM', 'knee_angle',   'W2_H2_Leading',    nan,   26 ;
     'ROM', 'knee_angle',   'W2_H2_Trailing',   nan,   nan ;
     'ROM', 'knee_angle',   'W2_H3_Leading',    nan,   31 ;
     'ROM', 'knee_angle',   'W2_H3_Trailing',   nan,   nan ;
     'ROM', 'knee_angle',   'Level_Walk',       nan,   nan ;
     'ROM', 'ankle_angle',  'W1_H1_Leading',    nan,   28 ;
     'ROM', 'ankle_angle',  'W1_H1_Trailing',   nan,   31 ;
     'ROM', 'ankle_angle',  'W1_H2_Leading',    nan,   nan ;
     'ROM', 'ankle_angle',  'W1_H2_Trailing',   nan,   29 ;
     'ROM', 'ankle_angle',  'W1_H3_Leading',    nan,   nan ;
     'ROM', 'ankle_angle',  'W1_H3_Trailing',   nan,   28 ;
     'ROM', 'ankle_angle',  'W2_H1_Leading',    nan,   nan ;
     'ROM', 'ankle_angle',  'W2_H1_Trailing',   nan,   27 ;
     'ROM', 'ankle_angle',  'W2_H2_Leading',    nan,   nan ;
     'ROM', 'ankle_angle',  'W2_H2_Trailing',   nan,   25 ;
     'ROM', 'ankle_angle',  'W2_H3_Leading',    nan,   nan ;
     'ROM', 'ankle_angle',  'W2_H3_Trailing',   nan,   29 ;
     'ROM', 'ankle_angle',  'Level_Walk',       nan,   nan ;
};
T1PARAMS = {'clr_toe','clr_heel','clr_min','lift_dist','land_dist'};   % Tier-1 (mm internally); stride is in the spatiotemporal set
T1LABEL  = {'Toe clearance','Heel clearance','Min clearance','Take-off dist','Landing dist'};
T1YLAB   = {'Clearance (cm)','Clearance (cm)','Clearance (cm)','Distance (cm)','Distance (cm)'};

%% -------------------- PLOT STYLE (template) --------------------
ST = struct();
ST.font      = 'Arial';
ST.szSgtitle = 18;     % overall layout title
ST.szTitle   = 16;     % panel title
ST.szLabel   = 16;     % axis labels (x/y)
ST.szTick    = 13;     % tick numbers
ST.szLegend  = 14;     % legend text
ST.szSub     = 12;     % layout subtitle
ST.boxWidth  = 2.0;    % axes box-border thickness
ST.barEdgeW  = 0.8;    % bar outline thickness
ST.errW      = 1.2;    % error-bar line thickness
ST.levelW    = 2.6;    % level-walk reference line thickness
ST.levelLblSz= 13;     % level-walk label font size
ST.pctSz     = 12;     % "% vs level" label font size (on bars)
ST.bold      = true;   % bold tick labels + axis labels
ST.gridOn    = false;  % template: grid off, box on
ST.pngDPI    = 300;    % PNG resolution
ST.savePDF   = false;  % PNG only (set true to also save a vector PDF)
ST.colLead   = [0.20 0.40 0.80];   % blue   - Leading limb
ST.colTrail  = [0.90 0.50 0.10];   % orange - Trailing limb
ST.colLevel  = [0.85 0.10 0.10];   % sharp red - Level-walk reference line (stands out)
FONT = ST.font;   % kept for any remaining references

root   = fileparts(fileparts(mfilename('fullpath')));
outDir = fullfile(root,'Results','Group Analysis');
figDir = fullfile(outDir,'Figures');
if ~isfolder(figDir), mkdir(figDir); end

% Crossing conditions (terrain x role) and ROM conditions (+ Level_Walk baseline)
condName = {};
for t = 1:numel(TERRAINS)
    for r = 1:numel(ROLES)
        condName{end+1} = sprintf('%s_%s', TERRAINS{t}, ROLES{r}); %#ok<SAGROW>
    end
end
condR = [condName, {'Level_Walk'}];
nT = numel(TESTS);  nC = numel(condName);  nCR = numel(condR);

% Per-participant condition means: [nTest x nCond]
P1 = struct();   for p = T1PARAMS,  P1.(p{1})   = nan(nT, nC);  end
ROM = struct();  for j = JOINTS,    ROM.(j{1})  = nan(nT, nCR); end
JMAX = struct(); for j = JOINTS,    JMAX.(j{1}) = nan(nT, nCR); end   % joint angle max (deg)
JMIN = struct(); for j = JOINTS,    JMIN.(j{1}) = nan(nT, nCR); end   % joint angle min (deg)
SROM = struct(); for g = SEGMENTS,  SROM.(g{1}) = nan(nT, nCR); end
SPT = struct();  for p = STPARAMS,  SPT.(p{1})  = nan(nT, nCR); end
PKT = struct();  for q = PKALL,     PKT.(q{1})  = nan(nT, nCR); end
PEX = struct();  for q = 1:size(PEAKDEF,1), PEX.(PEAKDEF{q,1}) = nan(nT, nCR); end   % peak excursion, deg
nCross = zeros(nT,1);  usedTests = false(nT,1);

% Data-driven SIGN normalization (hip joint + Dot segments). Corrects the
% inconsistent left/right & per-trial sign conventions before directional peaks are
% taken; ROM/timing are sign-robust. Knee/ankle joints are deliberately not included.
% Templates are loaded from signTemplates.mat (rebuild via signNormTools().build if
% the cohort changes).
SNT = signNormTools();
SIGN_TPL = SNT.load(root);
% Hand-calculated joint max/min (Analysis/manualJointValues.m) - replaces the drift-
% affected automatic value per participant, in step7's RAW convention. {} = none.
MANUAL = manualJointValues();

%% ===================== PER-PARTICIPANT AGGREGATION =====================
for ti = 1:nT
    tn = TESTS(ti);
    b  = testDir(root, tn);
    cpF = fullfile(b, sprintf('CrossingParams_Test%d.mat', tn));
    s5F = fullfile(b, sprintf('SegTrajectories_WithCamera_Test%d.mat', tn));
    sgF = fullfile(b, sprintf('SegmentedParams_Test%d.mat', tn));
    if ~isfile(cpF) || ~isfile(s5F) || ~isfile(sgF)
        warning('Test %d: missing outputs (run steps 4/7/8) - skipped.', tn);  continue;
    end
    CP = load(cpF);  CP = CP.CP;
    S5 = load(s5F);  fn = fieldnames(S5);  S5 = S5.(fn{1});
    Sg = load(sgF);  Sg = Sg.Seg;
    SgRaw = Sg;                                  % raw convention (for joint max/min, matches step7)
    Sg = SNT.apply(Sg, S5, SIGN_TPL, SEG_SYS);   % normalize hip/segment sign conventions (for peaks)
    usedTests(ti) = true;  nCross(ti) = numel(CP.crossing);

    % --- Tier 1: clearance + placement from CP (per crossing) ---
    acc = struct();
    for p = T1PARAMS, acc.(p{1}) = repmat({[]}, 1, nC); end
    for e = 1:numel(CP.crossing)
        c = CP.crossing(e);
        ci = find(strcmp(condName, sprintf('%s_%s', c.terrain, c.role)), 1);
        if isempty(ci), continue; end
        acc.clr_toe{ci}(end+1)   = c.clr_toe;
        acc.clr_heel{ci}(end+1)  = c.clr_heel;
        acc.clr_min{ci}(end+1)   = minClearance(c);
        acc.lift_dist{ci}(end+1) = c.lift_dist;
        acc.land_dist{ci}(end+1) = c.land_dist;
    end
    % participant means per condition  (stride length is computed in the spatiotemporal set)
    for ci = 1:nC
        for p = T1PARAMS, P1.(p{1})(ti,ci) = mean(acc.(p{1}){ci}, 'omitnan'); end
    end

    % --- Tier 2: joint ROM + IMU segment tilt ROM (max-min/stride), by role, incl Level ---
    % A per-participant clean spec (CLEAN) is applied ONLY to the matching test+signal.
    for j = JOINTS
        sp = cleanSpecFor(CLEAN, tn, j{1});
        % Joint max/min from the RAW signal (step7 convention), then apply hand values;
        % ROM = max - min (sign-invariant) now reflects the manual corrections.
        [mxv, mnv] = jointMaxMinByCond(SgRaw, S5, @(s,sw) sprintf('Joint: %s_%s', j{1}, lower(s)), condR, sp);
        [mxv, mnv] = applyManualStep9(MANUAL, tn, j{1}, condR, mxv, mnv);
        JMAX.(j{1})(ti,:) = mxv;  JMIN.(j{1})(ti,:) = mnv;  ROM.(j{1})(ti,:) = mxv - mnv;
    end
    for g = SEGMENTS
        sp = cleanSpecFor(CLEAN, tn, g{1});
        SROM.(g{1})(ti,:) = romByCond(Sg, S5, @(s,sw) sprintf('IMU: %s %s (%s) X', sw, g{1}, SEG_SYS), condR, sp);
    end

    % --- Spatiotemporal (crossing stride): stride cm, cadence steps/min, speed m/s ---
    spt = spatiotemporalByCond(Sg, S5, condR);
    for p = STPARAMS, SPT.(p{1})(ti,:) = spt.(p{1}); end
    % --- Peak timing RELATIVE TO OBSTACLE CLEARANCE (foot-height apex), % GC ---
    %     signed: negative = signal peaks before the foot clears the obstacle.
    %     Reference event (apex) timing itself is kept as FootHeight (absolute % GC).
    for j = PKT_JOINTS
        sp = cleanSpecFor(CLEAN, tn, j{1});
        PKT.(j{1})(ti,:) = peakTimeRelByCond(Sg, S5, @(s,sw) sprintf('Joint: %s_%s', j{1}, lower(s)), condR, sp, PK_EXTREMUM.(j{1}));
    end
    for g = PKT_SEGS
        sp = cleanSpecFor(CLEAN, tn, g{1});
        PKT.(g{1})(ti,:) = peakTimeRelByCond(Sg, S5, @(s,sw) sprintf('IMU: %s %s (%s) X', sw, g{1}, SEG_SYS), condR, sp, PK_EXTREMUM.(g{1}));
    end
    PKT.FootHeight(ti,:) = footHeightPeakTimeByCond(Sg, S5, condR, PK_EXTREMUM.FootHeight);
    % --- Named peak EXCURSIONS (whole cycle, referenced to begin-ZVP), deg ---
    for q = 1:size(PEAKDEF,1)
        sig = PEAKDEF{q,3};  ext = PEAKDEF{q,4};  sp = cleanSpecFor(CLEAN, tn, sig);
        if any(strcmp(sig, PK_JOINT_SIGS))
            lf = @(s,sw) sprintf('Joint: %s_%s', sig, lower(s));
        else
            lf = @(s,sw) sprintf('IMU: %s %s (%s) X', sw, sig, SEG_SYS);
        end
        PEX.(PEAKDEF{q,1})(ti,:) = peakExcByCond(Sg, S5, lf, ext, condR, sp);
    end
    fprintf('Test %3d: %d crossings aggregated.\n', tn, nCross(ti));
end

G.tests = TESTS(usedTests);  G.n = nnz(usedTests);
if G.n == 0, error('No participants had complete outputs. Nothing to aggregate.'); end
fprintf('\nAggregated %d participant(s): %s\n', G.n, mat2str(G.tests));

%% ===================== GROUP MEAN +/- SD (across participants) =====================
% Keep only used rows, then collapse over participants.
for p = T1PARAMS
    M = P1.(p{1})(usedTests,:);
    G.T1.(p{1}).mean = mean(M,1,'omitnan');  G.T1.(p{1}).sd = std(M,0,1,'omitnan');
    G.T1.(p{1}).n    = sum(~isnan(M),1);
end
for j = JOINTS
    M = ROM.(j{1})(usedTests,:);
    G.ROM.(j{1}).mean = mean(M,1,'omitnan');  G.ROM.(j{1}).sd = std(M,0,1,'omitnan');
    G.ROM.(j{1}).n    = sum(~isnan(M),1);
    MX = JMAX.(j{1})(usedTests,:);  MN = JMIN.(j{1})(usedTests,:);
    G.JMAX.(j{1}).mean = mean(MX,1,'omitnan');  G.JMAX.(j{1}).sd = std(MX,0,1,'omitnan');  G.JMAX.(j{1}).n = sum(~isnan(MX),1);
    G.JMIN.(j{1}).mean = mean(MN,1,'omitnan');  G.JMIN.(j{1}).sd = std(MN,0,1,'omitnan');  G.JMIN.(j{1}).n = sum(~isnan(MN),1);
end
for g = SEGMENTS
    M = SROM.(g{1})(usedTests,:);
    G.SROM.(g{1}).mean = mean(M,1,'omitnan');  G.SROM.(g{1}).sd = std(M,0,1,'omitnan');
    G.SROM.(g{1}).n    = sum(~isnan(M),1);
end
for p = STPARAMS
    M = SPT.(p{1})(usedTests,:);
    G.SPT.(p{1}).mean = mean(M,1,'omitnan');  G.SPT.(p{1}).sd = std(M,0,1,'omitnan');  G.SPT.(p{1}).n = sum(~isnan(M),1);
end
for q = PKALL
    M = PKT.(q{1})(usedTests,:);
    G.PKT.(q{1}).mean = mean(M,1,'omitnan');  G.PKT.(q{1}).sd = std(M,0,1,'omitnan');  G.PKT.(q{1}).n = sum(~isnan(M),1);
end
% Named peak excursions: group EXCURSION (mean+/-SD) and paired delta-vs-level.
lvIx = find(strcmp(condR,'Level_Walk'),1);
for q = 1:size(PEAKDEF,1)
    key = PEAKDEF{q,1};  M = PEX.(key)(usedTests,:);
    G.PEXc.(key).mean = mean(M,1,'omitnan');  G.PEXc.(key).sd = std(M,0,1,'omitnan');  G.PEXc.(key).n = sum(~isnan(M),1);
    D = M - M(:,lvIx);                                   % paired: each participant minus their own level walk
    G.PEXd.(key).mean = mean(D,1,'omitnan');  G.PEXd.(key).sd = std(D,0,1,'omitnan');  G.PEXd.(key).n = sum(~isnan(D),1);
end
G.condName = condName;  G.condR = condR;  G.terrains = TERRAINS;  G.roles = ROLES;
G.joints = JOINTS;  G.segments = SEGMENTS;  G.t1params = T1PARAMS;  G.stparams = STPARAMS;  G.pkall = PKALL;
G.pkExtremum = PK_EXTREMUM;  G.peakdef = PEAKDEF;  G.cohort = COHORT;  G.cleaning = CLEAN;
G.perParticipant = struct('T1',P1,'ROM',ROM,'JMAX',JMAX,'JMIN',JMIN,'SROM',SROM,'SPT',SPT,'PKT',PKT,'PEX',PEX,'tests',TESTS,'used',usedTests,'nCross',nCross);

%% ===================== APPLY MANUAL OVERRIDES =====================
% Each OVERRIDE row {GROUP, SIGNAL, CONDITION, MEAN, SD} replaces that one cell's
% mean and/or SD (NaN = keep computed). Condition is resolved by name. Applied
% before saving/plotting so all outputs are consistent.
for r = 1:size(OVERRIDE,1)
    gname = OVERRIDE{r,1};  key = OVERRIDE{r,2};  cond = OVERRIDE{r,3};
    mv = OVERRIDE{r,4};     sv  = OVERRIDE{r,5};
    if strcmp(gname,'T1'), conds = condName;  scaleOv = 10; else, conds = condR;  scaleOv = 1; end
    if ~isfield(G, gname) || ~isfield(G.(gname), key)
        warning('OVERRIDE row %d: unknown %s.%s - skipped.', r, gname, key);  continue;
    end
    ci = find(strcmp(conds, cond), 1);
    if isempty(ci)
        warning('OVERRIDE row %d: condition "%s" not valid for group %s - skipped.', r, cond, gname);  continue;
    end
    if ~isnan(mv), G.(gname).(key).mean(ci) = mv * scaleOv; end
    if ~isnan(sv), G.(gname).(key).sd(ci)   = sv * scaleOv; end
    if ~isnan(mv) || ~isnan(sv)   % only report rows that actually set something
        fprintf('  OVERRIDE: %-4s %-12s @ %-16s  mean=%s  sd=%s\n', gname, key, cond, ovStr(mv), ovStr(sv));
    end
end
G.override = OVERRIDE;

%% ===================== SAVE .mat =====================
if ~isfolder(outDir), mkdir(outDir); end
save(fullfile(outDir, sprintf('GroupCrossing_%s.mat', COHORT)), 'G');

%% ===================== EXCEL SUMMARY =====================
xlsFile = fullfile(outDir, sprintf('GroupCrossing_%s_Summary.xlsx', COHORT));
if isfile(xlsFile), delete(xlsFile); end
% Tier 1 sheet: rows = condition, cols = each param mean/SD (cm) + n
vnames = {'Condition'};
for pp = 1:numel(T1PARAMS)
    vnames = [vnames, {sprintf('%s_mean_cm',T1PARAMS{pp}), sprintf('%s_SD_cm',T1PARAMS{pp})}]; %#ok<AGROW>
end
vnames = [vnames, {'n_participants'}];
C = cell(nC, numel(vnames));
for ci = 1:nC
    C{ci,1} = condName{ci};  col = 2;  nn = 0;
    for pp = 1:numel(T1PARAMS)
        m = G.T1.(T1PARAMS{pp}).mean(ci)/10;  s = G.T1.(T1PARAMS{pp}).sd(ci)/10;  % mm->cm
        C{ci,col} = round(m,2);  C{ci,col+1} = round(s,2);  col = col+2;
        nn = max(nn, G.T1.(T1PARAMS{pp}).n(ci));
    end
    C{ci,end} = nn;
end
writetable(cell2table(C,'VariableNames',matlab.lang.makeValidName(vnames)), xlsFile, 'Sheet','Tier1_cm');
% ROM sheet: rows = condition (incl Level_Walk), cols = each joint mean/SD (deg) + n
vnamesR = {'Condition'};
for jj = 1:numel(JOINTS)
    vnamesR = [vnamesR, {sprintf('%s_ROM_mean_deg',JOINTS{jj}), sprintf('%s_ROM_SD_deg',JOINTS{jj})}]; %#ok<AGROW>
end
vnamesR = [vnamesR, {'n_participants'}];
CR = cell(nCR, numel(vnamesR));
for ci = 1:nCR
    CR{ci,1} = condR{ci};  col = 2;  nn = 0;
    for jj = 1:numel(JOINTS)
        CR{ci,col} = round(G.ROM.(JOINTS{jj}).mean(ci),1);
        CR{ci,col+1} = round(G.ROM.(JOINTS{jj}).sd(ci),1);  col = col+2;
        nn = max(nn, G.ROM.(JOINTS{jj}).n(ci));
    end
    CR{ci,end} = nn;
end
writetable(cell2table(CR,'VariableNames',matlab.lang.makeValidName(vnamesR)), xlsFile, 'Sheet','ROM_deg');
% Segment ROM sheet (IMU tilt, Dot): rows = condition (incl Level_Walk), deg
vnamesS = {'Condition'};
for gg = 1:numel(SEGMENTS)
    vnamesS = [vnamesS, {sprintf('%s_ROM_mean_deg',SEGMENTS{gg}), sprintf('%s_ROM_SD_deg',SEGMENTS{gg})}]; %#ok<AGROW>
end
vnamesS = [vnamesS, {'n_participants'}];
CS = cell(nCR, numel(vnamesS));
for ci = 1:nCR
    CS{ci,1} = condR{ci};  col = 2;  nn = 0;
    for gg = 1:numel(SEGMENTS)
        CS{ci,col}   = round(G.SROM.(SEGMENTS{gg}).mean(ci),1);
        CS{ci,col+1} = round(G.SROM.(SEGMENTS{gg}).sd(ci),1);  col = col+2;
        nn = max(nn, G.SROM.(SEGMENTS{gg}).n(ci));
    end
    CS{ci,end} = nn;
end
writetable(cell2table(CS,'VariableNames',matlab.lang.makeValidName(vnamesS)), xlsFile, 'Sheet','SegmentROM_deg');
writeGroupSheet(xlsFile, 'Spatiotemporal',   condR, STPARAMS, G.SPT);   % stride cm / cadence spm / speed m/s
writeGroupSheet(xlsFile, 'JointMax_deg',     condR, JOINTS, G.JMAX);    % joint angle max (hand-corrected where set)
writeGroupSheet(xlsFile, 'JointMin_deg',     condR, JOINTS, G.JMIN);    % joint angle min (hand-corrected where set)
writeGroupSheet(xlsFile, 'PeakTiming_vsClearance', condR, PKALL, G.PKT); % signed %GC rel. to foot apex (FootHeight = absolute ref)
pkKeys = PEAKDEF(:,1)';
writeGroupSheet(xlsFile, 'PeakExcursion_deg', condR, pkKeys, G.PEXc);   % offset-corrected excursion
writeGroupSheet(xlsFile, 'PeakDelta_deg',     condR, pkKeys, G.PEXd);   % paired delta vs level
fprintf('Saved summary -> %s\n', xlsFile);

% ----- SPSS-ready: ONE sheet, one row per participant, every variable as a column -----
writeSpssWide(fullfile(outDir, sprintf('GroupCrossing_%s_SPSS.xlsx', COHORT)), G);

%% ===================== MARKDOWN SUMMARY (easy to read / share) =====================
mdFile = fullfile(outDir, sprintf('GroupCrossing_%s_Results.md', COHORT));
fid = fopen(mdFile, 'w');
fprintf(fid, '# Group obstacle-crossing results — %s (n = %d)\n\n', COHORT, G.n);
fprintf(fid, '_Generated %s from `step9_group_crossing_analysis.m`._\n\n', char(datetime('now','Format','yyyy-MM-dd HH:mm')));
fprintf(fid, '- **Participants (tests):** %s\n', strjoin(cellstr(string(G.tests)), ', '));
fprintf(fid, '- **Conditions:** terrain = Width×Height (W1 = 5 cm, W2 = 15 cm; H1/H2/H3), split **Leading** vs **Trailing** limb. `Level_Walk` = baseline.\n');
fprintf(fid, '- **Values:** group mean ± SD across participants (per-participant mean per condition first). No normalization.\n');
pf = fieldnames(PK_EXTREMUM);
fprintf(fid, '- **Peak-timing extremum reported per signal:** %s.\n', ...
    strjoin(arrayfun(@(i) sprintf('%s = %s', pf{i}, PK_EXTREMUM.(pf{i})), 1:numel(pf),'uni',0), ', '));
if ~isempty(CLEAN)
    fprintf(fid, '- **Cleaning:** Test %d — %s ROM/peak cleaned (MAD-median; codes %s excluded) for a mid-trial thigh-IMU artifact.\n', ...
        CLEAN(1).test, strjoin(CLEAN(1).signals,'/'), strjoin(CLEAN(1).excludeCodes,', '));
end
fprintf(fid, '\n');
mdTable(fid, 'Tier 1 — clearance & foot placement (cm)', condName, T1PARAMS, T1LABEL, G.T1, 10, 1);
mdTable(fid, 'Spatiotemporal — crossing stride', condR, STPARAMS, ...
    {'Stride (cm)','Cadence (steps/min)','Speed (m/s)'}, G.SPT, 1, [0 0 2]);
mdTable(fid, 'Joint ROM (deg)', condR, JOINTS, JOINTS, G.ROM, 1, 1);
mdTable(fid, 'Joint angle MAX (deg)', condR, JOINTS, JOINTS, G.JMAX, 1, 1);
mdTable(fid, 'Joint angle MIN (deg)', condR, JOINTS, JOINTS, G.JMIN, 1, 1);
mdTable(fid, 'Segment tilt ROM (deg, Dot)', condR, SEGMENTS, SEGMENTS, G.SROM, 1, 1);
% Peak timing RELATIVE to obstacle clearance (foot apex), signed % GC (neg = before
% clearing); FootHeight is the reference event's own ABSOLUTE timing (% GC).
pktRel = [PKT_JOINTS, PKT_SEGS];
fprintf(fid, '> Peak timing is **relative to obstacle clearance** (foot-height apex = foot over the obstacle): signed %% gait cycle, **negative = the peak occurs before the foot clears**. `FootHeight` is the clearance event''s own absolute %% GC (the reference).\n\n');
mdTable(fid, 'Peak timing vs obstacle clearance (% GC, signed)', condR, pktRel, ...
    cellfun(@(k) sprintf('%s (%s)', k, PK_EXTREMUM.(k)), pktRel, 'uni',0), G.PKT, 1, 0);
mdTable(fid, 'Foot-clearance timing (absolute % GC, reference event)', condR, {'FootHeight'}, ...
    {sprintf('FootHeight (%s)', PK_EXTREMUM.FootHeight)}, G.PKT, 1, 0);
% Named peak angles: excursion (offset-corrected) + paired delta vs level, by role.
pP = strcmp(PEAKDEF(:,5),'P');  pS = strcmp(PEAKDEF(:,5),'S');
kP = PEAKDEF(pP,1)';  nP = PEAKDEF(pP,2)';   kS = PEAKDEF(pS,1)';  nS = PEAKDEF(pS,2)';
% Anatomical peak-figure groups (joint + its IMU segment per figure). Panel titles
% carry a (P)/(S) role tag so the headline-vs-exploratory split stays visible.
pkDisp = containers.Map(PEAKDEF(:,1), PEAKDEF(:,2));   % key -> display name
pkRole = containers.Map(PEAKDEF(:,1), PEAKDEF(:,5));   % key -> P/S
% Figure panel titles: flexion/extension framing with the tilt description in
% parentheses for the thigh segment; a [P]/[S] role tag on every panel.
pkFig = containers.Map('KeyType','char','ValueType','char');
pkFig('thigh_fwd')  = 'Thigh flexion (forward tilt)';
pkFig('thigh_back') = 'Thigh extension (backward tilt)';
pkTitle = @(k) sprintf('%s [%s]', pkFigName(k, pkDisp, pkFig), pkRole(k));
% Each figure = a joint ROW then its IMU-segment ROW; each row shows the directional
% peak(s) + that structure's ROM. A panel spec = {sourceStruct, key, title, ylab};
% [] leaves a tile empty. Peaks from G.PEXc; ROM from G.ROM (joints) / G.SROM (segs).
PK = 'Peak angle (deg)';  RM = 'ROM (deg)';
pk = @(k) {G.PEXc, k, pkTitle(k), PK};
PKFIGS = { ...
  'Group_Peak_HipThigh', 2, 3, 'Hip and thigh', 'Flexion / extension + ROM   (begin-ZVP referenced)', ...
     { pk('hip_pk_flex'), pk('hip_pk_ext'), {G.ROM,'hip_flexion','Hip ROM',RM}, ...
       pk('thigh_fwd'),   pk('thigh_back'), {G.SROM,'Thigh','Thigh ROM',RM} }; ...
  'Group_Peak_KneeShank', 2, 3, 'Knee and shank', 'Knee flexion + shank fore/aft tilt + ROM', ...
     { pk('knee_pk_flex'), {G.ROM,'knee_angle','Knee ROM',RM}, [], ...
       pk('shank_back'),   pk('shank_fwd'),  {G.SROM,'Shank','Shank ROM',RM} }; ...
  'Group_Peak_AnkleFoot', 2, 3, 'Ankle and foot', 'Ankle dorsi/plantarflexion + foot toe up/down + ROM', ...
     { pk('ank_plant'),    pk('ank_dorsi'),  {G.ROM,'ankle_angle','Ankle ROM',RM}, ...
       pk('foot_toedown'), pk('foot_toeup'), {G.SROM,'Foot','Foot ROM',RM} } };
fprintf(fid, '> Peaks are whole-cycle extrema referenced to the begin-ZVP (stance) posture, magnitude in the named direction. **Δ vs level walk is paired within participant.**\n\n');
mdTable(fid, 'Peak angles — PRIMARY — excursion (deg, offset-corrected)', condR, kP, nP, G.PEXc, 1, 1, true);
mdTable(fid, 'Peak angles — PRIMARY — Δ vs level walk (deg, paired)',     condR, kP, nP, G.PEXd, 1, 1, true);
mdTable(fid, 'Peak angles — SECONDARY — excursion (deg)',                 condR, kS, nS, G.PEXc, 1, 1, true);
mdTable(fid, 'Peak angles — SECONDARY — Δ vs level walk (deg, paired)',   condR, kS, nS, G.PEXd, 1, 1, true);
fclose(fid);
fprintf('Saved markdown -> %s\n', mdFile);

%% ===================== FIGURES =====================
% Each figure has a left-hand checkbox panel to show/hide displays (Leading /
% Trailing / Level-walk). The exported PNG/PDF render only the chart layout
% (not the checkboxes), with everything shown.
XLAB = strrep(TERRAINS,'_','\_');   % nicer tick labels: W1\_H1 ...

% ----- Tier 1: 2x3 tiles, x = terrain, Leading vs Trailing (cm) -----
[~, tl1, ctrl1] = makeToggleFigure(sprintf('Group Tier 1 (n=%d)',G.n), [40 40 1680 900], 2, 3);
leadB = gobjects(0); trailB = gobjects(0); leadE = gobjects(0); trailE = gobjects(0);  hbRef = [];
for pp = 1:numel(T1PARAMS)
    [mL,sL,mT,sT] = seriesByTerrain(G.T1.(T1PARAMS{pp}), condName, TERRAINS, ROLES, 1/10);
    ax = nexttile(tl1);
    [hb,heL,heT] = drawGroupedBars(ax, XLAB, mL,sL,mT,sT, T1YLAB{pp}, T1LABEL{pp}, ST);
    leadB(end+1)=hb(1); trailB(end+1)=hb(2); leadE(end+1)=heL; trailE(end+1)=heT; %#ok<SAGROW>
    if pp == 1, hbRef = hb; end
end
styleLayoutTitle(tl1, sprintf('Group obstacle-crossing parameters   (mean \\pm SD, n = %d)', G.n), ...
    'Camera foot clearance & placement, ZHC stride length', ST);
lg = legend(hbRef, {'Leading limb','Trailing limb'}, 'Orientation','horizontal', ...
    'FontName',ST.font,'FontSize',ST.szLegend);
lg.Layout.Tile = 'north';
addToggles(ctrl1, {{'Leading limb',[leadB,leadE]}, {'Trailing limb',[trailB,trailE]}});
saveFig(tl1, figDir, 'Group_Tier1', ST);

% ----- Peak angles + ROM, by joint+segment pair (bars = value, red line = level walk) -----
% Each figure: joint row then its IMU-segment row; directional peak(s) + ROM per row.
% Bars = the value, red dashed line = level walk (gap to red line = change vs level);
% paired Δ stays in the md/xlsx tables. Drawn before ROM-only figures.
for gg = 1:size(PKFIGS,1)
    drawComboFigure(PKFIGS{gg,6}, PKFIGS{gg,2}, PKFIGS{gg,3}, condR, TERRAINS, ROLES, XLAB, ST, ...
        figDir, PKFIGS{gg,1}, sprintf('%s peak angles and ROM   (n = %d)', PKFIGS{gg,4}, G.n), ...
        [PKFIGS{gg,5} '   —   red line = level walk']);
end

% (Joint & segment ROM are shown per panel inside the combo peak figures above, so
%  the standalone ROM figures are omitted. The ROM tables remain in the md/xlsx.)

% ----- Spatiotemporal: stride / cadence / speed (level-walk dashed) -----
drawPanelFigure(G.SPT, STPARAMS, STNICE, STYLAB, condR, TERRAINS, ROLES, XLAB, ST, ...
    figDir, 'Group_Spatiotemporal', sprintf('Group spatiotemporal   (crossing stride, by limb role; n = %d)', G.n), ...
    'Stride length, cadence, speed   —   dashed = level walk', true, 1, 3);

% ----- Peak timing vs obstacle clearance: joints + segments together (2x3) -----
% Signed % GC relative to the foot-clearance apex (0 = foot over obstacle; negative =
% peak before clearing). FootHeight (the reference event's own absolute timing) stays
% in the md/xlsx tables, no longer its own figure.
pktAll = [PKT_JOINTS, PKT_SEGS];
pktNice = arrayfun(@(i) sprintf('%s (%s)', pktAll{i}, PK_EXTREMUM.(pktAll{i})), 1:numel(pktAll), 'uni',0);
drawPanelFigure(G.PKT, pktAll, pktNice, 'Peak vs clearance (% GC)', condR, TERRAINS, ROLES, XLAB, ST, ...
    figDir, 'Group_PeakTiming', sprintf('Group peak timing vs obstacle clearance   (joints + segments; n = %d)', G.n), ...
    '0 = foot over obstacle (apex);  negative = peak BEFORE clearing', false, 2, 3);

% (Peak-angle figures now drawn above, before ROM — excursion values with the red
%  level-walk reference line. Paired Δ vs level walk remains in the md/xlsx tables.)

fprintf('Saved figures -> %s\n', figDir);
fprintf('\nDone. Group results for %d participant(s) in Results/Group Analysis/.\n', G.n);

%% ============================ functions ============================
function b = testDir(root, tn)
    b = fullfile(root,'Results','Parameters Output',['Test ' num2str(tn)]);
    if ~isfolder(b)
        b2 = fullfile('..','Results','Parameters Output',['Test ' num2str(tn)]);
        if isfolder(b2), b = b2; end
    end
end

function v = minClearance(c)
% Min foot clearance over the obstacle footprint = min(foot z while |y|<=w/2) - top.
% Uses the lower of toe/heel. From the stored crossing arc; NaN if nothing in-span.
    w = c.obs_w;  h = c.obs_h;  a = c.arc;
    inT = abs(a.yToe)  <= w/2;  inH = abs(a.yHeel) <= w/2;
    % Include the y=0 interpolated toe/heel heights so min clearance is always
    % <= the toe clearance (clr_toe = z_toe_cross - h).
    zs = [a.zToe(inT); a.zHeel(inH); c.z_toe_cross; c.z_heel_cross];
    zs = zs(~isnan(zs));
    if isempty(zs), v = NaN; else, v = min(zs) - h; end
end

function [mxv, mnv] = jointMaxMinByCond(Sg, S5, labelFun, condR, sp)
% Per-condition aggregate of per-stride MAX and MIN of a joint signal (deg), pooled
% by role like romByCond. Mean by default; robust median + MAD gate when sp is set.
% Call on the RAW (non sign-normalized) Sg so it matches step7's figure convention.
    if nargin < 5, sp = []; end
    mxv = nan(1,numel(condR));  mnv = nan(1,numel(condR));
    accX = repmat({[]},1,numel(condR));  accN = repmat({[]},1,numel(condR));
    sides = {'L','R'};  sideWord = {'Left','Right'};
    camT = {S5.camera.terrainL, S5.camera.terrainR};
    camR = {S5.camera.roleL,    S5.camera.roleR};
    zvp  = {Sg.zvpL, Sg.zvpR};  labels = {Sg.signal.label};
    for s = 1:2
        li = find(strcmp(labels, labelFun(sides{s}, sideWord{s})), 1);  if isempty(li), continue; end
        Y = Sg.signal(li).strides;
        mx = max(Y,[],1,'omitnan');  mn = min(Y,[],1,'omitnan');
        bad = all(isnan(Y),1);  mx(bad) = NaN;  mn(bad) = NaN;
        T = camT{s};  R = camR{s};  zv = zvp{s};  m = min(numel(mx), numel(T));
        for k = 1:m
            if isnan(mx(k)) || isempty(T{k}), continue; end
            if strcmpi(T{k},'Level_Walk'), ci = find(strcmp(condR,'Level_Walk'),1);  code = T{k};
            elseif ~isempty(R{k}),          ci = find(strcmp(condR, sprintf('%s_%s', T{k}, R{k})), 1);  code = T{k};
            else,                           ci = [];  code = '';
            end
            if isempty(ci), continue; end
            if ~isempty(sp)
                if ~isempty(sp.excludeCodes) && any(strcmp(code, sp.excludeCodes)), continue; end
                if ~isempty(sp.excludeWin) && k <= numel(zv)
                    tk = (zv(k)-1)/Sg.fs;
                    if any(tk >= sp.excludeWin(:,1) & tk <= sp.excludeWin(:,2)), continue; end
                end
            end
            accX{ci}(end+1) = mx(k);  accN{ci}(end+1) = mn(k);
        end
    end
    for ci = 1:numel(condR), mxv(ci) = aggStat(accX{ci}, sp);  mnv(ci) = aggStat(accN{ci}, sp); end
end

function v = aggStat(x, sp)
    x = x(~isnan(x));  if isempty(x), v = NaN; return; end
    if isempty(sp)
        v = mean(x);
    else
        if numel(x) >= 4 && isfinite(sp.madK)
            md = median(x);  ad = median(abs(x-md));
            if ad > 0, x = x(abs(x-md) <= sp.madK*1.4826*ad); end
        end
        v = median(x);
    end
end

function [mxv, mnv] = applyManualStep9(MJ, tn, joint, condR, mxv, mnv)
% Override per-condition joint max/min with hand-calculated values (the 'value' field;
% [] keeps the automatic one). Condition = <terrain>_<role>. The table's SD column is
% for step7's error bar only and is not used here.
    if isempty(MJ), return; end
    for r = 1:size(MJ,1)
        if ~isequal(MJ{r,1}, tn) || ~strcmp(MJ{r,2}, joint), continue; end
        terr = MJ{r,3};  role = MJ{r,4};  stat = lower(MJ{r,5});  val = MJ{r,6};
        if isempty(val), continue; end                      % [] = keep automatic
        ci = find(strcmp(condR, sprintf('%s_%s', terr, role)), 1);  if isempty(ci), continue; end
        if strcmp(stat,'max'), mxv(ci) = val; else, mnv(ci) = val; end
    end
end

function v = romByCond(Sg, S5, labelFun, condR, sp)
% ROM (max-min per stride, deg) for a signal, per condition (terrain x role,
% + Level_Walk), pooling the left and right instance by the stride's role.
% labelFun(side,'Left'/'Right') -> the Seg.signal label to use for that side.
% sp (optional, default []) = per-participant clean spec: when present, strides in
% sp.excludeCodes / sp.excludeWin are dropped and each condition is MAD-gated and
% aggregated with the MEDIAN; otherwise (default) the plain MEAN is used (unchanged).
    if nargin < 5, sp = []; end
    v = nan(1, numel(condR));
    acc = repmat({[]}, 1, numel(condR));
    sides = {'L','R'};  sideWord = {'Left','Right'};
    camT = {S5.camera.terrainL, S5.camera.terrainR};
    camR = {S5.camera.roleL,    S5.camera.roleR};
    zvp  = {Sg.zvpL, Sg.zvpR};
    labels = {Sg.signal.label};
    for s = 1:2
        li = find(strcmp(labels, labelFun(sides{s}, sideWord{s})), 1);
        if isempty(li), continue; end
        Y = Sg.signal(li).strides;                 % NSEG x nStr
        rom = max(Y,[],1,'omitnan') - min(Y,[],1,'omitnan');  % 1 x nStr
        rom(all(isnan(Y),1)) = NaN;
        T = camT{s};  R = camR{s};  zv = zvp{s};  m = min(numel(rom), numel(T));
        for k = 1:m
            if isnan(rom(k)) || isempty(T{k}), continue; end
            if strcmpi(T{k},'Level_Walk')
                ci = find(strcmp(condR,'Level_Walk'),1);  code = T{k};
            elseif ~isempty(R{k})
                ci = find(strcmp(condR, sprintf('%s_%s', T{k}, R{k})), 1);  code = T{k};
            else
                ci = [];  code = '';
            end
            if isempty(ci), continue; end
            if ~isempty(sp)                                   % per-participant exclusion (b)
                if ~isempty(sp.excludeCodes) && any(strcmp(code, sp.excludeCodes)), continue; end
                if ~isempty(sp.excludeWin) && k <= numel(zv)
                    tk = (zv(k)-1)/Sg.fs;                     % stride start time (s)
                    if any(tk >= sp.excludeWin(:,1) & tk <= sp.excludeWin(:,2)), continue; end
                end
            end
            acc{ci}(end+1) = rom(k);
        end
    end
    for ci = 1:numel(condR)
        x = acc{ci}(~isnan(acc{ci}));
        if isempty(sp)
            v(ci) = mean(x, 'omitnan');                       % default: unchanged
        else
            if numel(x) >= 4 && isfinite(sp.madK)             % (a) MAD gate
                md = median(x);  ad = median(abs(x-md));
                if ad > 0, x = x(abs(x-md) <= sp.madK*1.4826*ad); end
            end
            v(ci) = median(x, 'omitnan');                     % (a) robust aggregate
        end
    end
end

function sp = cleanSpecFor(CLEAN, tn, base)
% Return the per-participant clean spec for this test+signal, or [] (no cleaning).
    sp = [];
    for i = 1:numel(CLEAN)
        if CLEAN(i).test == tn && any(strcmp(base, CLEAN(i).signals)), sp = CLEAN(i); return; end
    end
end

function s = ovStr(v)
    if isnan(v), s = '(kept)'; else, s = num2str(v); end
end

function [ci, code] = condIdx(condR, terr, role)
% Map a stride's terrain/role to its condition index in condR (+ its terrain code).
    if strcmpi(terr,'Level_Walk')
        ci = find(strcmp(condR,'Level_Walk'),1);  code = terr;
    elseif ~isempty(role) && ~isempty(terr)
        ci = find(strcmp(condR, sprintf('%s_%s', terr, role)), 1);  code = terr;
    else
        ci = [];  code = '';
    end
end

function out = spatiotemporalByCond(Sg, S5, condR)
% Per-condition crossing-stride means: stride length (cm), cadence (steps/min),
% speed (m/s), from ZHC net-XY displacement and the ZVP->ZVP stride time. L/R
% pooled by role; includes Level_Walk.
    acS = repmat({[]},1,numel(condR));  acC = acS;  acV = acS;
    sides = {'L','R'};
    camT = {S5.camera.terrainL, S5.camera.terrainR};
    camR = {S5.camera.roleL,    S5.camera.roleR};
    zvp  = {Sg.zvpL, Sg.zvpR};  fs = Sg.fs;
    for s = 1:2
        if ~isfield(Sg.zhc, sides{s}), continue; end
        pos = Sg.zhc.(sides{s}).posGait;  nWin = size(pos,3);
        T = camT{s};  R = camR{s};  zv = zvp{s};  m = min([nWin, numel(T), numel(zv)-1]);
        for k = 1:m
            [ci,~] = condIdx(condR, T{k}, R{k});  if isempty(ci), continue; end
            X = pos(:,1,k);  Y = pos(:,2,k);  if all(isnan(X)), continue; end
            Lmm = hypot(X(end)-X(1), Y(end)-Y(1)) * 1000;   % m -> mm
            Ts  = (zv(k+1)-zv(k)) / fs;                     % stride time (s)
            if ~(Ts > 0), continue; end
            acS{ci}(end+1) = Lmm/10;            % cm
            acC{ci}(end+1) = 120/Ts;            % steps/min (2 steps per stride)
            acV{ci}(end+1) = (Lmm/1000)/Ts;     % m/s
        end
    end
    out.stride  = cellfun(@(x) mean(x,'omitnan'), acS);
    out.cadence = cellfun(@(x) mean(x,'omitnan'), acC);
    out.speed   = cellfun(@(x) mean(x,'omitnan'), acV);
end

function v = peakExcByCond(Sg, S5, labelFun, ext, condR, sp)
% Mean peak EXCURSION (deg, magnitude in the named direction) = |extremum over the
% whole cycle - begin-ZVP reference|, per condition, pooled by role. Same per-
% participant cleaning (sp) as romByCond. Sg is already sign-normalized at load
% (see signNormTools), so a single ext convention is valid across sides.
    if nargin < 6, sp = []; end
    REFW = 4;                                        % samples for the begin-ZVP reference median
    v = nan(1, numel(condR));  acc = repmat({[]},1,numel(condR));
    sides = {'L','R'};  sideWord = {'Left','Right'};
    camT = {S5.camera.terrainL, S5.camera.terrainR};
    camR = {S5.camera.roleL,    S5.camera.roleR};
    zvp  = {Sg.zvpL, Sg.zvpR};  labels = {Sg.signal.label};
    for s = 1:2
        li = find(strcmp(labels, labelFun(sides{s}, sideWord{s})), 1);  if isempty(li), continue; end
        Y = Sg.signal(li).strides;                   % NSEG x nStr (sign-normalized at load)
        ref = median(Y(1:min(REFW,size(Y,1)),:), 1, 'omitnan');
        if strcmpi(ext,'min')
            exc = ref - min(Y,[],1,'omitnan');                 % dip below stance
        elseif strcmpi(ext,'abs')
            exc = max(abs(Y - ref),[],1,'omitnan');            % largest deviation (sign-invariant)
        else
            exc = max(Y,[],1,'omitnan') - ref;                 % rise above stance
        end
        exc(all(isnan(Y),1)) = NaN;
        T = camT{s};  R = camR{s};  zv = zvp{s};  m = min(numel(exc), numel(T));
        for k = 1:m
            if isnan(exc(k)) || isempty(T{k}), continue; end
            [ci,code] = condIdx(condR, T{k}, R{k});  if isempty(ci), continue; end
            if ~isempty(sp)
                if ~isempty(sp.excludeCodes) && any(strcmp(code, sp.excludeCodes)), continue; end
                if ~isempty(sp.excludeWin) && k <= numel(zv)
                    tk = (zv(k)-1)/Sg.fs;
                    if any(tk >= sp.excludeWin(:,1) & tk <= sp.excludeWin(:,2)), continue; end
                end
            end
            acc{ci}(end+1) = exc(k);
        end
    end
    for ci = 1:numel(condR)
        x = acc{ci}(~isnan(acc{ci}));
        if isempty(sp)
            v(ci) = mean(x, 'omitnan');
        else
            if numel(x) >= 4 && isfinite(sp.madK)
                md = median(x);  ad = median(abs(x-md));
                if ad > 0, x = x(abs(x-md) <= sp.madK*1.4826*ad); end
            end
            v(ci) = median(x, 'omitnan');
        end
    end
end

function nm = pkFigName(key, pkDisp, pkFig)
% Figure panel name for a peak key: the flexion/extension override if one exists,
% otherwise the formal PEAKDEF display name.
    if isKey(pkFig, key), nm = pkFig(key); else, nm = pkDisp(key); end
end

function v = peakTimeRelByCond(Sg, S5, labelFun, condR, sp, ext)
% Mean peak timing of a signal RELATIVE TO OBSTACLE CLEARANCE, per condition, in
% % gait cycle. For each stride: signalPeak%GC - footApex%GC, where the foot apex
% (max foot height, Sg.zhc.posGait Z) is the "foot over the top of the obstacle"
% instant. Signed: negative = the signal peaks BEFORE clearance, positive = after.
% Same per-stride pooling + cleaning (sp) as the ROM/peak helpers.
    if nargin < 5, sp = []; end
    if nargin < 6 || isempty(ext), ext = 'max'; end
    NSEG = Sg.nseg;  v = nan(1, numel(condR));  acc = repmat({[]},1,numel(condR));
    sides = {'L','R'};  sideWord = {'Left','Right'};
    camT = {S5.camera.terrainL, S5.camera.terrainR};
    camR = {S5.camera.roleL,    S5.camera.roleR};
    zvp  = {Sg.zvpL, Sg.zvpR};  labels = {Sg.signal.label};
    for s = 1:2
        li = find(strcmp(labels, labelFun(sides{s}, sideWord{s})), 1);  if isempty(li), continue; end
        if ~isfield(Sg.zhc, sides{s}), continue; end
        Y = Sg.signal(li).strides;                 % NSEG x nStr (sign-normalized at load)
        if strcmpi(ext,'min'), [~, pk] = min(Y, [], 1); else, [~, pk] = max(Y, [], 1); end
        pkpct = (pk-1)/(NSEG-1)*100;  pkpct(all(isnan(Y),1)) = NaN;
        pos = Sg.zhc.(sides{s}).posGait;  nWin = size(pos,3);
        T = camT{s};  R = camR{s};  zv = zvp{s};  m = min([numel(pkpct), numel(T), nWin]);
        for k = 1:m
            if isnan(pkpct(k)) || isempty(T{k}), continue; end
            Z = pos(:,3,k);  if all(isnan(Z)), continue; end
            [~, ap] = max(Z);  apexpct = (ap-1)/(NSEG-1)*100;     % foot-over-obstacle instant
            [ci,code] = condIdx(condR, T{k}, R{k});  if isempty(ci), continue; end
            if ~isempty(sp)
                if ~isempty(sp.excludeCodes) && any(strcmp(code, sp.excludeCodes)), continue; end
                if ~isempty(sp.excludeWin) && k <= numel(zv)
                    tk = (zv(k)-1)/Sg.fs;
                    if any(tk >= sp.excludeWin(:,1) & tk <= sp.excludeWin(:,2)), continue; end
                end
            end
            acc{ci}(end+1) = pkpct(k) - apexpct;                 % relative to clearance
        end
    end
    for ci = 1:numel(condR)
        x = acc{ci}(~isnan(acc{ci}));
        if isempty(sp)
            v(ci) = mean(x, 'omitnan');
        else
            if numel(x) >= 4 && isfinite(sp.madK)
                md = median(x);  ad = median(abs(x-md));
                if ad > 0, x = x(abs(x-md) <= sp.madK*1.4826*ad); end
            end
            v(ci) = median(x, 'omitnan');
        end
    end
end

function v = footHeightPeakTimeByCond(Sg, S5, condR, ext)
% Mean peak-height timing (% gait cycle) of the foot (ZHC Z) per condition.
    if nargin < 4 || isempty(ext), ext = 'max'; end
    NSEG = Sg.nseg;  v = nan(1, numel(condR));  acc = repmat({[]},1,numel(condR));
    sides = {'L','R'};
    camT = {S5.camera.terrainL, S5.camera.terrainR};
    camR = {S5.camera.roleL,    S5.camera.roleR};
    for s = 1:2
        if ~isfield(Sg.zhc, sides{s}), continue; end
        pos = Sg.zhc.(sides{s}).posGait;  nWin = size(pos,3);
        T = camT{s};  R = camR{s};  m = min(nWin, numel(T));
        for k = 1:m
            Z = pos(:,3,k);  if all(isnan(Z)), continue; end
            [ci,~] = condIdx(condR, T{k}, R{k});  if isempty(ci), continue; end
            if strcmpi(ext,'min'), [~,pk] = min(Z); else, [~,pk] = max(Z); end
            acc{ci}(end+1) = (pk-1)/(NSEG-1)*100;
        end
    end
    for ci = 1:numel(condR), v(ci) = mean(acc{ci}, 'omitnan'); end
end

function mdTable(fid, header, conds, keys, niceHdr, S, divisor, dec, pctOff)
% Write one Markdown table: rows = condition, cols = each key's "mean ± SD", + n.
% If the conditions include Level_Walk (and pctOff not set), each non-level cell
% also gets (% vs level).
    if nargin < 9, pctOff = false; end
    if isscalar(dec), dec = repmat(dec,1,numel(keys)); end
    lvi = find(strcmp(conds,'Level_Walk'),1);  if pctOff, lvi = []; end
    fprintf(fid, '## %s\n\n', header);
    fprintf(fid, '| Condition | %s | n |\n', strjoin(niceHdr, ' | '));
    fprintf(fid, '%s|\n', repmat('|---', 1, numel(keys)+2));
    for ci = 1:numel(conds)
        fprintf(fid, '| %s ', conds{ci});  nn = 0;
        for k = 1:numel(keys)
            m = S.(keys{k}).mean(ci);  sd = S.(keys{k}).sd(ci);
            if isnan(m)
                cell = '–';
            else
                cell = sprintf('%.*f ± %.*f', dec(k), m/divisor, dec(k), sd/divisor);
                if ~isempty(lvi) && ci ~= lvi
                    lv = S.(keys{k}).mean(lvi);
                    if isfinite(lv) && lv ~= 0, cell = sprintf('%s (%+.0f%%)', cell, (m-lv)/lv*100); end
                end
            end
            fprintf(fid, '| %s ', cell);
            nn = max(nn, S.(keys{k}).n(ci));
        end
        fprintf(fid, '| %d |\n', nn);
    end
    fprintf(fid, '\n');
end

function writeSpssWide(xlsFile, G)
% ONE sheet, one row per participant, each KEPT parameter x condition as a column
% (values to 3 decimals). Import directly into SPSS. Column = <group>_<key>_<cond>.
% Edit EXCLUDE to tailor which variables are written. Prints a legend to the console.
    EXCLUDE = { 'T1','clr_toe';  'T1','clr_heel';            % keep only min clearance
                'ROM','hip_flexion';  'ROM','knee_angle';     % remove hip & knee joint ROM (keep ankle)
                'SROM','Thigh';  'SROM','Shank';              % remove thigh & shank segment ROM (keep foot)
                'PEX','hip_pk_ext';  'PEX','thigh_back' };     % remove hip extension & thigh backward tilt
    pp = G.perParticipant;  tests = pp.tests(:);  condR = G.condR;
    T = table(tests, 'VariableNames', {'Test'});
    GRP = { 'T1',G.t1params; 'SPT',G.stparams; 'ROM',G.joints; 'JMAX',G.joints; ...
            'JMIN',G.joints; 'SROM',G.segments; 'PEX',G.peakdef(:,1)'; 'PKT',G.pkall };
    for gi = 1:size(GRP,1)
        grp = GRP{gi,1};  keys = GRP{gi,2};
        for k = 1:numel(keys)
            if any(strcmp(EXCLUDE(:,1),grp) & strcmp(EXCLUDE(:,2),keys{k})), continue; end   % tailored out
            M = round(pp.(grp).(keys{k}), 3);  conds = condR(1:size(M,2));
            for c = 1:numel(conds)
                T.(matlab.lang.makeValidName(sprintf('%s_%s_%s', grp, keys{k}, conds{c}))) = M(:,c);
            end
        end
    end
    if isfile(xlsFile), delete(xlsFile); end
    writetable(T, xlsFile);
    fprintf('Saved SPSS sheet (one row/participant, %d variables, 3 decimals) -> %s\n', width(T)-1, xlsFile);
    printSpssLegend(G, GRP, EXCLUDE);
end

function printSpssLegend(G, GRP, EXCLUDE)
% Explain the SPSS column naming <group>_<key>_<condition> in the command window.
    grpDesc = {'T1','clearance / foot placement (cm)'; 'SPT','spatiotemporal';
               'ROM','joint range of motion = max-min (deg)'; 'JMAX','joint angle maximum (deg)';
               'JMIN','joint angle minimum (deg)'; 'SROM','segment tilt ROM (deg, Dot)';
               'PEX','peak angle excursion from stance (deg)'; 'PKT','peak timing vs obstacle clearance (% gait cycle, signed: - = before clearing)'};
    keyDesc = {'clr_min','minimum foot clearance over the obstacle'; 'lift_dist','take-off distance (foot before obstacle)';
               'land_dist','landing distance (foot after obstacle)'; 'stride','stride length (cm)';
               'cadence','cadence (steps/min)'; 'speed','gait speed (m/s)';
               'hip_flexion','hip'; 'knee_angle','knee'; 'ankle_angle','ankle';
               'Thigh','thigh segment'; 'Shank','shank segment'; 'Foot','foot segment';
               'hip_pk_flex','hip peak flexion'; 'knee_pk_flex','knee peak flexion';
               'ank_plant','ankle peak plantarflexion'; 'ank_dorsi','ankle peak dorsiflexion';
               'thigh_fwd','thigh peak forward tilt'; 'shank_back','shank peak backward (heel-up)';
               'shank_fwd','shank peak forward (reach)'; 'foot_toedown','foot peak toe-down';
               'foot_toeup','foot peak toe-up'; 'FootHeight','peak foot-height (clearance) timing'};
    fprintf('\n--- SPSS variable legend (column = GROUP_key_CONDITION) ---\n');
    fprintf('GROUPS:\n');
    for i = 1:size(grpDesc,1), fprintf('  %-5s = %s\n', grpDesc{i,1}, grpDesc{i,2}); end
    fprintf('KEYS (kept):\n');
    kept = {};
    for gi = 1:size(GRP,1)
        for k = 1:numel(GRP{gi,2})
            if ~any(strcmp(EXCLUDE(:,1),GRP{gi,1}) & strcmp(EXCLUDE(:,2),GRP{gi,2}{k})), kept{end+1} = GRP{gi,2}{k}; end %#ok<AGROW>
        end
    end
    for k = unique(kept,'stable')
        d = keyDesc(strcmp(keyDesc(:,1),k{1}),2);  if isempty(d), d = {k{1}}; end
        fprintf('  %-13s = %s\n', k{1}, d{1});
    end
    fprintf('CONDITIONS:  W1/W2 = width (5 cm / 15 cm) ; H1/H2/H3 = height ; _Leading / _Trailing = limb role ; Level_Walk = baseline\n');
    fprintf('  e.g. ROM_ankle_angle_W2_H3_Trailing = ankle ROM, 15cm-wide tallest obstacle, trailing limb\n\n');
end

function writeGroupSheet(xlsFile, sheet, conds, keys, S)
% Write one summary sheet: rows = condition, cols = each key's mean/SD + n.
    vn = {'Condition'};
    for k = 1:numel(keys), vn = [vn, {[keys{k} '_mean'], [keys{k} '_SD']}]; end %#ok<AGROW>
    vn = [vn, {'n_participants'}];
    C = cell(numel(conds), numel(vn));
    for ci = 1:numel(conds)
        C{ci,1} = conds{ci};  col = 2;  nn = 0;
        for k = 1:numel(keys)
            C{ci,col} = round(S.(keys{k}).mean(ci),2);  C{ci,col+1} = round(S.(keys{k}).sd(ci),2);  col = col+2;
            nn = max(nn, S.(keys{k}).n(ci));
        end
        C{ci,end} = nn;
    end
    writetable(cell2table(C,'VariableNames',matlab.lang.makeValidName(vn)), xlsFile, 'Sheet', sheet);
end

function [mL,sL,mT,sT] = seriesByTerrain(S, condList, terrains, roles, scale)
% Pull mean/SD for Leading and Trailing series, ordered by terrain, scaled.
    nTT = numel(terrains);
    [mL,sL,mT,sT] = deal(nan(1,nTT));
    for t = 1:nTT
        iL = find(strcmp(condList, sprintf('%s_%s', terrains{t}, roles{1})), 1);
        iT = find(strcmp(condList, sprintf('%s_%s', terrains{t}, roles{2})), 1);
        if ~isempty(iL), mL(t) = S.mean(iL)*scale;  sL(t) = S.sd(iL)*scale; end
        if ~isempty(iT), mT(t) = S.mean(iT)*scale;  sT(t) = S.sd(iT)*scale; end
    end
end

function [hb, hebL, hebT, pctH] = drawGroupedBars(ax, cats, mL, sL, mT, sT, ylab, ttl, ST, levelVal)
% Grouped bars (Leading vs Trailing) with SD error bars, styled from ST. The
% Leading/Trailing error bars are separate objects so each series (bars + its
% error bars) can be toggled together. Box on + thick border, grid per ST.gridOn.
% If levelVal (the signal's level-walk mean) is given, the % change vs level walk
% is printed above each bar.
    if nargin < 10, levelVal = []; end
    fw = 'normal';  if ST.bold, fw = 'bold'; end
    hold(ax,'on');  box(ax,'on');
    M = [mL(:), mT(:)];  Sd = [sL(:), sT(:)];
    hb = bar(ax, M, 'grouped', 'BarWidth', 0.9);
    hb(1).FaceColor = ST.colLead;   hb(2).FaceColor = ST.colTrail;
    hb(1).EdgeColor = [0.20 0.20 0.20];  hb(2).EdgeColor = [0.20 0.20 0.20];
    hb(1).LineWidth = ST.barEdgeW;  hb(2).LineWidth = ST.barEdgeW;
    xb = [hb(1).XEndPoints(:), hb(2).XEndPoints(:)];
    hebL = errorbar(ax, xb(:,1), M(:,1), Sd(:,1), 'linestyle','none', ...
        'Color',[0.15 0.15 0.15], 'LineWidth',ST.errW, 'CapSize',4, 'HandleVisibility','off');
    hebT = errorbar(ax, xb(:,2), M(:,2), Sd(:,2), 'linestyle','none', ...
        'Color',[0.15 0.15 0.15], 'LineWidth',ST.errW, 'CapSize',4, 'HandleVisibility','off');
    ax.XTick = 1:numel(cats);  ax.XTickLabel = cats;  ax.TickLabelInterpreter = 'tex';
    xtickangle(ax, 20);
    ax.FontName = ST.font;  ax.FontSize = ST.szTick;  ax.FontWeight = fw;
    ax.LineWidth = ST.boxWidth;  ax.XColor = [0.15 0.15 0.15];  ax.YColor = [0.15 0.15 0.15];
    if ST.gridOn, ax.YGrid = 'on';  ax.XGrid = 'off';  ax.GridAlpha = 0.15; else, grid(ax,'off'); end
    % % change vs level walk, printed (vertical) above each bar (toggleable via pctH)
    pctH = gobjects(0);
    if ~isempty(levelVal) && isfinite(levelVal) && levelVal ~= 0
        yl = ylim(ax);  off = diff(yl)*0.02;
        for g = 1:2
            for t = 1:numel(cats)
                v = M(t,g);  if isnan(v), continue; end
                yt = v;  if ~isnan(Sd(t,g)), yt = v + Sd(t,g); end
                pctH(end+1) = text(ax, xb(t,g), yt+off, sprintf('%+.0f%%', (v-levelVal)/levelVal*100), ...
                    'Rotation',90, 'FontName',ST.font, 'FontSize',ST.pctSz, 'FontWeight','bold', ...
                    'Color',[0.25 0.25 0.25], 'HorizontalAlignment','left', 'VerticalAlignment','middle'); %#ok<AGROW>
            end
        end
        yl = ylim(ax);  ylim(ax, [yl(1), yl(2) + diff(yl)*0.22]);   % headroom for the % labels
    end
    ylabel(ax, ylab, 'FontName',ST.font, 'FontSize',ST.szLabel, 'FontWeight',fw);
    title(ax, ttl, 'FontName',ST.font, 'FontSize',ST.szTitle, 'FontWeight','bold', 'Interpreter','none');
end

function f = drawPanelFigure(S, keys, nice, ylabs, condList, terrains, roles, xlab, ST, figDir, fname, ttl, subttl, showLevel, rows, cols)
% General tiled grouped-bar figure (Leading vs Trailing by terrain), with an
% optional level-walk dashed baseline per panel and show/hide checkboxes. ylabs
% may be one string (shared) or a cell of per-panel labels. Exports the layout.
    if ischar(ylabs) || isstring(ylabs), ylabs = repmat({char(ylabs)}, 1, numel(keys)); end
    w = min(1680, 540*cols);  h = 320 + 300*rows;
    [f, tl, ctrl] = makeToggleFigure(ttl, [50 50 w h], rows, cols);
    leadB = gobjects(0); trailB = gobjects(0); leadE = gobjects(0); trailE = gobjects(0);
    lvl = gobjects(0);  pctAll = gobjects(0);  hbRef = [];
    for k = 1:numel(keys)
        [mL,sL,mT,sT] = seriesByTerrain(S.(keys{k}), condList, terrains, roles, 1);
        lw = S.(keys{k}).mean(strcmp(condList,'Level_Walk'));
        ax = nexttile(tl);
        lvArg = []; if showLevel, lvArg = lw; end          % % change vs level printed on bars
        [hb,heL,heT,pH] = drawGroupedBars(ax, xlab, mL,sL,mT,sT, ylabs{k}, nice{k}, ST, lvArg);
        leadB(end+1)=hb(1); trailB(end+1)=hb(2); leadE(end+1)=heL; trailE(end+1)=heT; %#ok<AGROW>
        if ~isempty(pH), pctAll = [pctAll, pH(:)']; end     %#ok<AGROW>
        if showLevel
            if ~isnan(lw)
                yl = yline(ax, lw, '--', 'level walk', 'Color', ST.colLevel, 'LineWidth',ST.levelW, 'FontName',ST.font, ...
                      'FontSize',ST.levelLblSz, 'LabelHorizontalAlignment','left', 'LabelVerticalAlignment','bottom');
                lvl(end+1) = yl; %#ok<AGROW>
            end
        else
            yline(ax, 0, '-', 'Color',[0.45 0.45 0.45], 'LineWidth',1.4, 'HandleVisibility','off');  % Δ zero reference
        end
        if k == 1, hbRef = hb; end
    end
    styleLayoutTitle(tl, ttl, subttl, ST);
    lg = legend(hbRef, {'Leading limb','Trailing limb'}, 'Orientation','horizontal', ...
        'FontName',ST.font,'FontSize',ST.szLegend);
    lg.Layout.Tile = 'north';
    grp = {{'Leading limb',[leadB,leadE]}, {'Trailing limb',[trailB,trailE]}};
    if ~isempty(lvl),    grp{end+1} = {'Level walk', lvl}; end
    if ~isempty(pctAll), grp{end+1} = {'% vs level', pctAll}; end
    addToggles(ctrl, grp);
    saveFig(tl, figDir, fname, ST);
end

function f = drawComboFigure(specs, rows, cols, condList, terrains, roles, xlab, ST, figDir, fname, ttl, subttl)
% Mixed-source grouped-bar figure: each panel spec = {S, key, title, ylab} (S is any
% struct with .(key).mean/.sd over condList, e.g. G.PEXc / G.ROM / G.SROM), or [] for
% an empty tile. Bars = value, red dashed line = that panel's level-walk value, with
% the same Leading/Trailing/Level/% toggles and layout export as drawPanelFigure.
    w = min(1740, 560*cols);  h = 320 + 300*rows;
    [f, tl, ctrl] = makeToggleFigure(ttl, [50 50 w h], rows, cols);
    leadB = gobjects(0); trailB = gobjects(0); leadE = gobjects(0); trailE = gobjects(0);
    lvl = gobjects(0);  pctAll = gobjects(0);  hbRef = [];
    for p = 1:numel(specs)
        ax = nexttile(tl);
        sp = specs{p};
        if isempty(sp), axis(ax,'off'); continue; end
        S = sp{1};  key = sp{2};  ttlP = sp{3};  ylab = sp{4};
        [mL,sL,mT,sT] = seriesByTerrain(S.(key), condList, terrains, roles, 1);
        lw = S.(key).mean(strcmp(condList,'Level_Walk'));
        [hb,heL,heT,pH] = drawGroupedBars(ax, xlab, mL,sL,mT,sT, ylab, ttlP, ST, lw);
        leadB(end+1)=hb(1); trailB(end+1)=hb(2); leadE(end+1)=heL; trailE(end+1)=heT; %#ok<AGROW>
        if ~isempty(pH), pctAll = [pctAll, pH(:)']; end %#ok<AGROW>
        if ~isnan(lw)
            yl = yline(ax, lw, '--', 'level walk', 'Color', ST.colLevel, 'LineWidth',ST.levelW, 'FontName',ST.font, ...
                  'FontSize',ST.levelLblSz, 'LabelHorizontalAlignment','left', 'LabelVerticalAlignment','bottom');
            lvl(end+1) = yl; %#ok<AGROW>
        end
        if isempty(hbRef), hbRef = hb; end
    end
    styleLayoutTitle(tl, ttl, subttl, ST);
    lg = legend(hbRef, {'Leading limb','Trailing limb'}, 'Orientation','horizontal', ...
        'FontName',ST.font,'FontSize',ST.szLegend);
    lg.Layout.Tile = 'north';
    grp = {{'Leading limb',[leadB,leadE]}, {'Trailing limb',[trailB,trailE]}};
    if ~isempty(lvl),    grp{end+1} = {'Level walk', lvl}; end
    if ~isempty(pctAll), grp{end+1} = {'% vs level', pctAll}; end
    addToggles(ctrl, grp);
    saveFig(tl, figDir, fname, ST);
end

function [f, tl, ctrl] = makeToggleFigure(name, pos, rows, cols)
% Figure with a narrow left checkbox panel and the tiled chart layout on the
% right. Exporting the returned layout (tl) excludes the checkbox panel.
    f = figure('Color','w','Name',name,'Position',pos);
    ctrl  = uipanel(f,'Units','normalized','Position',[0 0 0.072 1],'BackgroundColor','w','BorderType','none');
    right = uipanel(f,'Units','normalized','Position',[0.072 0 0.928 1],'BackgroundColor','w','BorderType','none');
    tl = tiledlayout(right, rows, cols, 'TileSpacing','compact','Padding','compact');
end

function addToggles(ctrl, groups)
% Stacked checkboxes: each toggles the Visible state of a handle group.
    uicontrol(ctrl,'Style','text','Units','normalized','Position',[0.05 0.955 0.9 0.03], ...
        'String','Show','BackgroundColor','w','FontName','Arial','FontSize',10,'FontWeight','bold', ...
        'HorizontalAlignment','left');
    for i = 1:numel(groups)
        uicontrol(ctrl,'Style','checkbox','Units','normalized', ...
            'Position',[0.05, 0.91-(i-1)*0.05, 0.93, 0.045], ...
            'String',groups{i}{1},'Value',1,'BackgroundColor','w','FontName','Arial','FontSize',9, ...
            'Callback',@(src,~) setVis(groups{i}{2}, src.Value));
    end
end

function setVis(harr, on)
    v = 'off';  if on, v = 'on'; end
    for h = harr(:)'
        if isgraphics(h), h.Visible = v; end
    end
end

function styleLayoutTitle(tl, ttl, subttl, ST)
    title(tl, ttl, 'FontName',ST.font,'FontSize',ST.szSgtitle,'FontWeight','bold','Interpreter','tex');
    if ~isempty(subttl)
        subtitle(tl, subttl, 'FontName',ST.font,'FontSize',ST.szSub,'Color',[0.35 0.35 0.35],'Interpreter','tex');
    end
end

function saveFig(tl, figDir, name, ST)
% High-res PNG (always) + vector PDF if ST.savePDF. Exports the LAYOUT only, so
% the checkbox panel is excluded; hides axes toolbars first.
    f = ancestor(tl, 'figure');
    axs = findall(f, 'Type', 'axes');
    for a = 1:numel(axs)
        try
            axtoolbar(axs(a), {});
        catch
        end
        if ~isempty(axs(a).Toolbar), axs(a).Toolbar.Visible = 'off'; end
    end
    exportgraphics(tl, fullfile(figDir, [name '.png']), 'Resolution', ST.pngDPI);
    if ST.savePDF
        try
            exportgraphics(tl, fullfile(figDir, [name '.pdf']), 'ContentType', 'vector');
        catch
        end
    end
end
