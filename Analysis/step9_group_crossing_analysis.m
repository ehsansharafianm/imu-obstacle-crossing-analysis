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
TESTS    = [101 102 103 104 105 106];  % participant test numbers (Subject ID = Test #)
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
SROM = struct(); for g = SEGMENTS,  SROM.(g{1}) = nan(nT, nCR); end
SPT = struct();  for p = STPARAMS,  SPT.(p{1})  = nan(nT, nCR); end
PKT = struct();  for q = PKALL,     PKT.(q{1})  = nan(nT, nCR); end
nCross = zeros(nT,1);  usedTests = false(nT,1);

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
        ROM.(j{1})(ti,:) = romByCond(Sg, S5, @(s,sw) sprintf('Joint: %s_%s', j{1}, lower(s)), condR, sp);
    end
    for g = SEGMENTS
        sp = cleanSpecFor(CLEAN, tn, g{1});
        SROM.(g{1})(ti,:) = romByCond(Sg, S5, @(s,sw) sprintf('IMU: %s %s (%s) X', sw, g{1}, SEG_SYS), condR, sp);
    end

    % --- Spatiotemporal (crossing stride): stride cm, cadence steps/min, speed m/s ---
    spt = spatiotemporalByCond(Sg, S5, condR);
    for p = STPARAMS, SPT.(p{1})(ti,:) = spt.(p{1}); end
    % --- Peak timing (% gait cycle, ZVP->ZVP): joints, segments, foot height ---
    for j = PKT_JOINTS
        sp = cleanSpecFor(CLEAN, tn, j{1});
        PKT.(j{1})(ti,:) = peakTimeByCond(Sg, S5, @(s,sw) sprintf('Joint: %s_%s', j{1}, lower(s)), condR, sp, PK_EXTREMUM.(j{1}));
    end
    for g = PKT_SEGS
        sp = cleanSpecFor(CLEAN, tn, g{1});
        PKT.(g{1})(ti,:) = peakTimeByCond(Sg, S5, @(s,sw) sprintf('IMU: %s %s (%s) X', sw, g{1}, SEG_SYS), condR, sp, PK_EXTREMUM.(g{1}));
    end
    PKT.FootHeight(ti,:) = footHeightPeakTimeByCond(Sg, S5, condR, PK_EXTREMUM.FootHeight);
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
G.condName = condName;  G.condR = condR;  G.terrains = TERRAINS;  G.roles = ROLES;
G.joints = JOINTS;  G.segments = SEGMENTS;  G.t1params = T1PARAMS;  G.stparams = STPARAMS;  G.pkall = PKALL;
G.pkExtremum = PK_EXTREMUM;  G.cohort = COHORT;  G.cleaning = CLEAN;
G.perParticipant = struct('T1',P1,'ROM',ROM,'SROM',SROM,'SPT',SPT,'PKT',PKT,'tests',TESTS,'used',usedTests,'nCross',nCross);

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
writeGroupSheet(xlsFile, 'PeakTiming_pctGC', condR, PKALL,    G.PKT);   % % gait cycle
fprintf('Saved summary -> %s\n', xlsFile);

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
mdTable(fid, 'Segment tilt ROM (deg, Dot)', condR, SEGMENTS, SEGMENTS, G.SROM, 1, 1);
mdTable(fid, 'Peak timing (% gait cycle)', condR, PKALL, ...
    cellfun(@(k) sprintf('%s (%s)', k, PK_EXTREMUM.(k)), PKALL, 'uni',0), G.PKT, 1, 0);
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

% ----- Joint ROM: 1x3 tiles (hip/knee/ankle), Level-walk dashed -----
drawRomFigure(G.ROM, JOINTS, {'Hip flexion','Knee','Ankle'}, condR, TERRAINS, ROLES, XLAB, ST, ...
    figDir, 'Group_JointROM', ...
    sprintf('Group joint ROM   (max-min per stride, by limb role; n = %d)', G.n), ...
    'Lower-limb joint excursion   —   dashed = level-walk baseline');

% ----- IMU segment tilt ROM: 1x3 tiles (Foot/Shank/Thigh, Dot) -----
drawRomFigure(G.SROM, SEGMENTS, SEGMENTS, condR, TERRAINS, ROLES, XLAB, ST, ...
    figDir, 'Group_SegmentROM', ...
    sprintf('Group IMU segment tilt ROM   (Dot reference, by limb role; n = %d)', G.n), ...
    'Foot / Shank / Thigh orientation excursion   —   dashed = level-walk baseline');

% ----- Spatiotemporal: stride / cadence / speed (level-walk dashed) -----
drawPanelFigure(G.SPT, STPARAMS, STNICE, STYLAB, condR, TERRAINS, ROLES, XLAB, ST, ...
    figDir, 'Group_Spatiotemporal', sprintf('Group spatiotemporal   (crossing stride, by limb role; n = %d)', G.n), ...
    'Stride length, cadence, speed   —   dashed = level walk', true, 1, 3);

% ----- Peak timing (% gait cycle): joints (1x3) -----
jn = {'Hip flexion','Knee','Ankle'};
jnE = arrayfun(@(i) sprintf('%s (%s)', jn{i}, PK_EXTREMUM.(PKT_JOINTS{i})), 1:numel(PKT_JOINTS), 'uni',0);
drawPanelFigure(G.PKT, PKT_JOINTS, jnE, 'Gait cycle (%)', condR, TERRAINS, ROLES, XLAB, ST, ...
    figDir, 'Group_PeakTiming_Joints', sprintf('Group joint peak timing   (%% gait cycle, ZVP\\rightarrowZVP; n = %d)', G.n), ...
    'When the joint max/min occurs in the crossing cycle   —   dashed = level walk', true, 1, 3);

% ----- Peak timing (% gait cycle): foot height (own figure) -----
drawPanelFigure(G.PKT, {'FootHeight'}, {sprintf('Foot height (%s)', PK_EXTREMUM.FootHeight)}, 'Gait cycle (%)', condR, TERRAINS, ROLES, XLAB, ST, ...
    figDir, 'Group_PeakTiming_FootHeight', sprintf('Group foot-height peak timing   (%% gait cycle; n = %d)', G.n), ...
    'When peak foot clearance occurs in the crossing cycle   —   dashed = level walk', true, 1, 1);

% ----- Peak timing (% gait cycle): segments (1x3) -----
sgE = arrayfun(@(i) sprintf('%s (%s)', PKT_SEGS{i}, PK_EXTREMUM.(PKT_SEGS{i})), 1:numel(PKT_SEGS), 'uni',0);
drawPanelFigure(G.PKT, PKT_SEGS, sgE, 'Gait cycle (%)', condR, TERRAINS, ROLES, XLAB, ST, ...
    figDir, 'Group_PeakTiming_Segments', sprintf('Group segment peak timing   (%% gait cycle; n = %d)', G.n), ...
    'Foot / Shank / Thigh tilt peak   —   dashed = level walk', true, 1, 3);

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

function v = peakTimeByCond(Sg, S5, labelFun, condR, sp, ext)
% Mean peak timing (% gait cycle) of a signal per condition: arg-extremum (max or
% min, per ext) of each normalized stride. Same per-participant cleaning (sp).
    if nargin < 5, sp = []; end
    if nargin < 6 || isempty(ext), ext = 'max'; end
    NSEG = Sg.nseg;  v = nan(1, numel(condR));  acc = repmat({[]},1,numel(condR));
    sides = {'L','R'};  sideWord = {'Left','Right'};
    camT = {S5.camera.terrainL, S5.camera.terrainR};
    camR = {S5.camera.roleL,    S5.camera.roleR};
    zvp  = {Sg.zvpL, Sg.zvpR};  labels = {Sg.signal.label};
    for s = 1:2
        li = find(strcmp(labels, labelFun(sides{s}, sideWord{s})), 1);  if isempty(li), continue; end
        Y = Sg.signal(li).strides;                 % NSEG x nStr
        if strcmpi(ext,'min'), [~, pk] = min(Y, [], 1); else, [~, pk] = max(Y, [], 1); end
        pkpct = (pk-1)/(NSEG-1)*100;
        pkpct(all(isnan(Y),1)) = NaN;
        T = camT{s};  R = camR{s};  zv = zvp{s};  m = min(numel(pkpct), numel(T));
        for k = 1:m
            if isnan(pkpct(k)) || isempty(T{k}), continue; end
            [ci,code] = condIdx(condR, T{k}, R{k});  if isempty(ci), continue; end
            if ~isempty(sp)
                if ~isempty(sp.excludeCodes) && any(strcmp(code, sp.excludeCodes)), continue; end
                if ~isempty(sp.excludeWin) && k <= numel(zv)
                    tk = (zv(k)-1)/Sg.fs;
                    if any(tk >= sp.excludeWin(:,1) & tk <= sp.excludeWin(:,2)), continue; end
                end
            end
            acc{ci}(end+1) = pkpct(k);
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

function mdTable(fid, header, conds, keys, niceHdr, S, divisor, dec)
% Write one Markdown table: rows = condition, cols = each key's "mean ± SD", + n.
    if isscalar(dec), dec = repmat(dec,1,numel(keys)); end
    fprintf(fid, '## %s\n\n', header);
    fprintf(fid, '| Condition | %s | n |\n', strjoin(niceHdr, ' | '));
    fprintf(fid, '%s|\n', repmat('|---', 1, numel(keys)+2));
    for ci = 1:numel(conds)
        fprintf(fid, '| %s ', conds{ci});  nn = 0;
        for k = 1:numel(keys)
            m = S.(keys{k}).mean(ci)/divisor;  sd = S.(keys{k}).sd(ci)/divisor;
            if isnan(m), cell = '–'; else, cell = sprintf('%.*f ± %.*f', dec(k), m, dec(k), sd); end
            fprintf(fid, '| %s ', cell);
            nn = max(nn, S.(keys{k}).n(ci));
        end
        fprintf(fid, '| %d |\n', nn);
    end
    fprintf(fid, '\n');
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

function [hb, hebL, hebT] = drawGroupedBars(ax, cats, mL, sL, mT, sT, ylab, ttl, ST)
% Grouped bars (Leading vs Trailing) with SD error bars, styled from ST. The
% Leading/Trailing error bars are separate objects so each series (bars + its
% error bars) can be toggled together. Box on + thick border, grid per ST.gridOn.
    fw = 'normal';  if ST.bold, fw = 'bold'; end
    hold(ax,'on');  box(ax,'on');
    M = [mL(:), mT(:)];  Sd = [sL(:), sT(:)];
    hb = bar(ax, M, 'grouped', 'BarWidth', 0.9);
    hb(1).FaceColor = ST.colLead;   hb(2).FaceColor = ST.colTrail;
    hb(1).EdgeColor = [0.20 0.20 0.20];  hb(2).EdgeColor = [0.20 0.20 0.20];
    hb(1).LineWidth = ST.barEdgeW;  hb(2).LineWidth = ST.barEdgeW;
    hebL = errorbar(ax, hb(1).XEndPoints, M(:,1), Sd(:,1), 'linestyle','none', ...
        'Color',[0.15 0.15 0.15], 'LineWidth',ST.errW, 'CapSize',4, 'HandleVisibility','off');
    hebT = errorbar(ax, hb(2).XEndPoints, M(:,2), Sd(:,2), 'linestyle','none', ...
        'Color',[0.15 0.15 0.15], 'LineWidth',ST.errW, 'CapSize',4, 'HandleVisibility','off');
    ax.XTick = 1:numel(cats);  ax.XTickLabel = cats;  ax.TickLabelInterpreter = 'tex';
    xtickangle(ax, 20);
    ax.FontName = ST.font;  ax.FontSize = ST.szTick;  ax.FontWeight = fw;
    ax.LineWidth = ST.boxWidth;  ax.XColor = [0.15 0.15 0.15];  ax.YColor = [0.15 0.15 0.15];
    if ST.gridOn, ax.YGrid = 'on';  ax.XGrid = 'off';  ax.GridAlpha = 0.15; else, grid(ax,'off'); end
    ylabel(ax, ylab, 'FontName',ST.font, 'FontSize',ST.szLabel, 'FontWeight',fw);
    title(ax, ttl, 'FontName',ST.font, 'FontSize',ST.szTitle, 'FontWeight','bold', 'Interpreter','none');
end

function f = drawRomFigure(S, keys, nice, condR, terrains, roles, xlab, ST, figDir, fname, ttl, subttl)
% Thin wrapper: a 1 x nKeys ROM (deg) panel figure with the level-walk baseline.
    f = drawPanelFigure(S, keys, nice, 'ROM (deg)', condR, terrains, roles, xlab, ST, ...
        figDir, fname, ttl, subttl, true, 1, numel(keys));
end

function f = drawPanelFigure(S, keys, nice, ylabs, condList, terrains, roles, xlab, ST, figDir, fname, ttl, subttl, showLevel, rows, cols)
% General tiled grouped-bar figure (Leading vs Trailing by terrain), with an
% optional level-walk dashed baseline per panel and show/hide checkboxes. ylabs
% may be one string (shared) or a cell of per-panel labels. Exports the layout.
    if ischar(ylabs) || isstring(ylabs), ylabs = repmat({char(ylabs)}, 1, numel(keys)); end
    w = min(1680, 540*cols);  h = 320 + 300*rows;
    [f, tl, ctrl] = makeToggleFigure(ttl, [50 50 w h], rows, cols);
    leadB = gobjects(0); trailB = gobjects(0); leadE = gobjects(0); trailE = gobjects(0);
    lvl = gobjects(0);  hbRef = [];
    for k = 1:numel(keys)
        [mL,sL,mT,sT] = seriesByTerrain(S.(keys{k}), condList, terrains, roles, 1);
        ax = nexttile(tl);
        [hb,heL,heT] = drawGroupedBars(ax, xlab, mL,sL,mT,sT, ylabs{k}, nice{k}, ST);
        leadB(end+1)=hb(1); trailB(end+1)=hb(2); leadE(end+1)=heL; trailE(end+1)=heT; %#ok<AGROW>
        if showLevel
            lw = S.(keys{k}).mean(strcmp(condList,'Level_Walk'));
            if ~isnan(lw)
                yl = yline(ax, lw, '--', 'level walk', 'Color', ST.colLevel, 'LineWidth',ST.levelW, 'FontName',ST.font, ...
                      'FontSize',ST.levelLblSz, 'LabelHorizontalAlignment','left', 'LabelVerticalAlignment','bottom');
                lvl(end+1) = yl; %#ok<AGROW>
            end
        end
        if k == 1, hbRef = hb; end
    end
    styleLayoutTitle(tl, ttl, subttl, ST);
    lg = legend(hbRef, {'Leading limb','Trailing limb'}, 'Orientation','horizontal', ...
        'FontName',ST.font,'FontSize',ST.szLegend);
    lg.Layout.Tile = 'north';
    grp = {{'Leading limb',[leadB,leadE]}, {'Trailing limb',[trailB,trailE]}};
    if ~isempty(lvl), grp{end+1} = {'Level walk', lvl}; end
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
