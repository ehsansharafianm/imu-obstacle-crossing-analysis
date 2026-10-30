function build_crossing_master(tests)
% BUILD_CROSSING_MASTER  Crossing-level master dataset for ML training (young adults).
%
%   build_crossing_master            % Tests 101-110
%   build_crossing_master(101:109)   % any subset
%
% One row = one obstacle crossing (participant x obstacle x repeat) or one level
% walk (is_level = 1). Both limbs are in the same row, named by ROLE (lead_ /
% trail_), not by side. Wearable features come from the Dot IMUs only (thigh /
% shank / foot sagittal tilt, foot acceleration, ZHC foot trajectory, ZVP gait
% events). The camera is REFERENCE/TARGET only. No Awinda or OpenSim joint angles.
%
% Kept SEPARATE from the per-participant pipeline (steps 1-9): it only READS their
% outputs and never writes into Results/Parameters Output or Group Analysis.
%   SegmentedParams_TestN.mat         step 4: ZVP, toe-off, heel-strike, ZHC trajectory
%   SegTrajectories_WithCamera_TestN  step 7: per-cycle terrain / role (sign templates)
%   CrossingParams_TestN.mat          step 8: camera clearance, take-off, landing
%   CameraSynced_TestN.mat            step 5: camera markers on the IMU clock + shift
%   AllData_TestN.mat                 step 3: Dot angles / acc / gyro / quaternion
%   Data/Camera CV/Test N/testN_crossings.xlsx : crossing list, lead/trail leg, y=0 times
%   Analysis/signTemplates.mat        sign normalization of the Dot segments (step 9)
%
% STRIDE = ZVP -> ZVP (mid-stance to mid-stance), exactly as steps 4-9. SWING =
% the step-4 toe-off -> heel-strike that fall inside that stride; every _max/_min/
% _rom/_t_*/_av_*/_acc_* value is taken over the swing, and every % is % of swing.
% Definitions of every column: data_dictionary.md (written by this function).
%
% Output -> Results/ML Dataset/
%   Crossing_Master_YoungAdults.csv      the dataset (Test 106 thigh MAD gate applied)
%   Crossing_Curves_YoungAdults.csv      per row: lead and trail swing curves (thigh/shank/foot tilt,
%                                        foot acc, ZHC height and progression), 0-100% swing, for the ML
%   exclusions_log.csv                   every cleaned / missing value with reason; the original of
%                                        every cleaned value (so the raw data are recoverable), and
%                                        the values an all-participant gate WOULD remove (not applied)
%   data_dictionary.md                   name, role, unit, definition, sign, source
%   build_report.md                      row counts, missingness, ranges, SPSS check
% Participant descriptors come from Analysis/ML/participants_meta.csv (a template
% is created on the first run; fill it in by hand - nothing is guessed).

if nargin < 1 || isempty(tests), tests = 101:110; end
here = fileparts(mfilename('fullpath'));
root = fileparts(fileparts(here));
addpath(fileparts(here));                                % Analysis/ (signNormTools)

%% ===================== CONFIG =====================
CFG.cohort       = 'YoungAdults';
CFG.segs         = {'thigh','Thigh'; 'shank','Shank'; 'foot','Foot'};   % column key, Dot label
CFG.refW         = 4;        % begin-ZVP neutral = median of first 4 normalized samples (step9 REFW)
CFG.accWinFrac   = 0.25;     % acc "near swing initiation / landing" = first / last 25% of swing
CFG.gravity      = 9.80665;
CFG.omegaThr     = 24;       % step-4 still-foot thresholds (|gyro|, |acc| incl. gravity)
CFG.accThr       = 21;
CFG.driftMadK    = 3;        % zhc_drift_flag: |uncorrected landing drift| > median + 3*MAD (cohort)
CFG.maxStride_s  = 2.5;      % a crossing / level stride longer than this is not a walking stride -> flag
CFG.zvpNearW     = 5;        % step-8 sampleNear window (frames)
CFG.markerR_mm   = 20;       % step-8 obstacle marker radius
CFG.zhcPeak_mm   = [10 800]; % plausible ZHC peak foot height  -> else trajectory_invalid
CFG.zhcStride_mm = [200 2500];
CFG.appMaxDur_s  = 2.0;      % approach stride must be a walking stride (not a turn / pause)
CFG.appMinLen_mm = 300;
CFG.lvPad_s      = 0.5;      % level passes: ignore toe y=0 crossings inside obstacle passes +/- pad
CFG.lvPairTol_s  = 1.5;      % L and R y=0 crossings within this -> same level pass
CFG.lvDedup_s    = 1.0;
CFG.lvMinRise_mm = 100;      % toe must move +y through y=0 (swing, walking direction)
CFG.clean        = struct('test',106,'vars',{{'thigh_max','thigh_min','thigh_rom','thigh_max_corr','thigh_min_corr'}},'madK',3);
CFG.cleanAll     = struct('test',tests,'vars',{CFG.clean.vars},'madK',3);   % v2 sensitivity file
CFG.heightPct    = [10 20 30];
CFG.width_cm     = [5 15];
CFG.decimals     = 4;
CFG.curveN       = 51;       % swing curves exported at 0:2:100 % swing
CFG.curveSig     = {'thigh','shank','foot','footacc','zhc_h','zhc_x'};
CFG.imuApexK     = 2.0;      % IMU-only crossing stride: ZHC stride apex > 2 x participant median apex
CFG.imuPairTol_s = 1.5;      % lead and trail apexes of one crossing within this
CFG.imuMatchTol_s = 1.5;     % IMU crossing matched to the camera crossing within this (evaluation only)
CFG.syncGap_s    = 0.3;      % |IMU apex - camera y=0 time| above this = timing mismatch (diagnosis)

outDir = fullfile(root,'Results','ML Dataset');
if ~isfolder(outDir), mkdir(outDir); end
SPEC  = columnSpec();
names = SPEC(:,1)';
textCols = {'crossing_id','obstacle_code','height_class','width_class','order_randomized', ...
            'leading_limb','sex','dominant_leg','cleaned_variables','role_imu'};
assert(numel(names) == 191, 'column spec has %d columns, expected 191', numel(names));

meta = loadMeta(fullfile(here,'participants_meta.csv'), tests, root);
SNT  = signNormTools();
TPL  = SNT.load(root);

%% ===================== BUILD ROWS PER PARTICIPANT =====================
rows = [];  SIDE = {};  QC = {};
for tn = tests
    fprintf('Test %d ...\n', tn);
    [r, s, q] = participantRows(tn, root, CFG, SNT, TPL, meta, names, textCols);
    if isempty(r), QC{end+1} = q; continue; end %#ok<AGROW>
    rows = [rows, r];  SIDE = [SIDE; s];  QC{end+1} = q; %#ok<AGROW>
    fprintf('  %d crossing rows, %d level rows\n', sum([r.is_level]==0), sum([r.is_level]==1));
end
if isempty(rows), error('No rows built - are the pipeline outputs present?'); end
[rows, CFG.driftThr_mm] = driftFlags(rows, CFG);
[rows, TOE] = toeHeights(rows);
rows = blockIds(rows);
D    = struct2table(rows, 'AsArray', true);        % all fields incl. internal ones (report only)
Traw = D(:, names);

%% ===================== CLEANING (raw kept) + EXCLUSIONS LOG =====================
[Tcl, xlog] = applyCleaning(Traw, CFG.clean);
xlog = [xlog; missingLog(Tcl, SPEC)];
[~, xall] = applyCleaning(Traw, CFG.cleanAll);              % sensitivity only: logged, not applied
sens = xall(~ismember(cell2mat(xall(:,1)), CFG.clean.test), :);
sens(:,6) = {'sensitivity only (not applied)'};
xlog = [xlog; sens];

%% ===================== WRITE =====================
base = sprintf('Crossing_Master_%s', CFG.cohort);
writeCsv(fullfile(outDir,[base '.csv']), Tcl, textCols, CFG.decimals);
writeLog(fullfile(outDir,'exclusions_log.csv'), xlog);
writeCurves(fullfile(outDir, sprintf('Crossing_Curves_%s.csv', CFG.cohort)), D, CFG);
writeDictionary(fullfile(outDir,'data_dictionary.md'), SPEC, CFG);
writeReport(fullfile(outDir,'build_report.md'), Tcl, Traw, SIDE, QC, SPEC, CFG, root, xlog);
writeReview(fullfile(outDir,'build_report.md'), Tcl, D, QC, TOE, xall, meta, CFG);
fprintf('\nWrote %d rows x %d columns -> %s\n', height(Tcl), width(Tcl), outDir);
end

%% ========================================================================
%  PER PARTICIPANT
%% ========================================================================
function [rows, side, qc] = participantRows(tn, root, CFG, SNT, TPL, meta, names, textCols)
rows = [];  side = {};
qc = struct('tn',tn,'notes',{{}},'nUnlab',0,'nLevelPass',0,'lvFeatLogAgree',NaN,'footSignR',[NaN NaN], ...
            'lvCand',[0 0],'lvFeatBouts',[0 0],'imu',struct('nEvents',0,'nPairs',0,'nUnmatched',0,'thr_mm',NaN));
b = fullfile(root,'Results','Parameters Output',sprintf('Test %d',tn));
need = {'SegmentedParams','Seg'; 'SegTrajectories_WithCamera','S5'; 'CrossingParams','CP'; ...
        'CameraSynced','Cam'; 'AllData','Data'};
V = struct();
for k = 1:size(need,1)
    f = fullfile(b, sprintf('%s_Test%d.mat', need{k,1}, tn));
    if ~isfile(f), qc.notes{end+1} = sprintf('missing %s - participant skipped', need{k,1}); warning('%s', qc.notes{end}); return; end
    d = load(f, need{k,2});  V.(need{k,2}) = d.(need{k,2});
end
Seg = V.Seg;  S5 = V.S5;  CP = V.CP;  Cam = V.Cam;  Data = V.Data;
xf = fullfile(root,'Data','Camera CV',sprintf('Test %d',tn),sprintf('test%d_crossings.xlsx',tn));
if ~isfile(xf), qc.notes{end+1} = 'missing camera crossings file - skipped'; return; end
C = readtable(xf,'Sheet','crossings','VariableNamingRule','preserve');

fs = Seg.fs;  t = Data.time(:);
if numel(Cam.time) ~= numel(t) || max(abs(Cam.time(:) - t)) > 1e-6     % put camera on the IMU grid
    mk = fieldnames(Cam.markers);
    for k = 1:numel(mk), Cam.markers.(mk{k}) = interp1(Cam.time(:), Cam.markers.(mk{k}), t, 'linear', NaN); end
    qc.notes{end+1} = 'camera time base differed from Dot time - markers interpolated onto Dot time';
end
shift = NaN;  if isfield(Cam,'sync') && isfield(Cam.sync,'shift_s'), shift = Cam.sync.shift_s; end

% ---- Dot signals per side (sign-normalized exactly as step 9) ----
SgN = SNT.apply(Seg, S5, TPL, 'Dot');
labs = {Seg.signal.label};  ilab = {Data.imu.label};
X = struct();
for sd = 'LR'
    w = sideWord(sd);
    for q = 1:size(CFG.segs,1)
        key = CFG.segs{q,1};  nm = CFG.segs{q,2};
        ii = find(strcmp(ilab, sprintf('%s %s (Dot)', w, nm)), 1);
        kk = find(strcmp(labs, sprintf('IMU: %s %s (Dot) X', w, nm)), 1);
        if isempty(ii) || isempty(kk), X.(sd).(key) = []; continue; end
        a = Seg.signal(kk).strides;  bN = SgN.signal(kk).strides;  g = isfinite(a) & a ~= 0;
        sg = 1;  if any(g(:)) && median(bN(g)./a(g)) < 0, sg = -1; end
        ang = sg * Data.imu(ii).euler_ZXY_deg(:,2);
        X.(sd).(key) = struct('ang',ang, 'av',gradient(ang)*fs, 'ref',bN, 'flip',sg);
    end
    iF = find(strcmp(ilab, sprintf('%s Foot (Dot)', w)), 1);
    acc = Data.imu(iF).acc;  gyr = Data.imu(iF).gyro;
    [X.(sd).accW, X.(sd).accWv] = worldAccMag(Data.imu(iF).quat, acc, CFG.gravity);
    X.(sd).still = vecnorm(gyr,2,2) < CFG.omegaThr & vecnorm(acc,2,2) < CFG.accThr;
    X.(sd).zvp  = Seg.(['zvp' sd])(:);
    X.(sd).toe  = Seg.(['toe' sd])(:);
    X.(sd).hs   = Seg.(['hs' sd])(:);
    X.(sd).zhc  = [];  X.(sd).pZvp = [];
    if isfield(Seg,'zhc') && isfield(Seg.zhc, sd), X.(sd).zhc = Seg.zhc.(sd).posTime; X.(sd).pZvp = Seg.zhc.(sd).pZvp; end
    X.(sd).terr = S5.camera.(['terrain' sd]);
    X.(sd).role = S5.camera.(['role' sd]);
    X.(sd).toeM  = Cam.markers.([sd '_toe']);
    X.(sd).heelM = Cam.markers.([sd '_heel']);
end
obsZ = obstacleMean(Cam, 3);  obsY = obstacleMean(Cam, 2);
cpKey = containers.Map('KeyType','char','ValueType','double');
for e = 1:numel(CP.crossing), cpKey(sprintf('%s%d', CP.crossing(e).side, CP.crossing(e).cyc)) = e; end

M = meta(meta.participant_id == tn, :);
r0 = emptyRow(names, textCols);
r0.lead_zhc_raw_drift = NaN;  r0.trail_zhc_raw_drift = NaN;   % internal (drift flag), not written
r0.lead_toefit = [];  r0.trail_toefit = [];                   % internal (toe geometry fit)
r0.lead_cam_heel_peak = NaN;  r0.trail_cam_heel_peak = NaN;      % internal (task 4 diagnosis)
r0.lead_curve = nan(1, CFG.curveN * numel(CFG.curveSig));  r0.trail_curve = r0.lead_curve;   % curves file
r0.lead_cyc = NaN;  r0.trail_cyc = NaN;  r0.stepchk = [NaN NaN]; % internal (IMU role, step-length check)
r0.participant_id = tn;  r0.dot_cam_sync_offset_s = shift;
if ~isempty(M)
    r0.age_y = M.age_y(1);  r0.sex = char(M.sex(1));  r0.dominant_leg = char(M.dominant_leg(1));
    r0.body_height_cm = M.body_height_cm(1);  r0.leg_length_cm = M.leg_length_cm(1);
    r0.mass_kg = M.mass_kg(1);  r0.order_randomized = char(M.order_randomized(1));
end

% ---------------- obstacle crossings ----------------
repCount = containers.Map('KeyType','char','ValueType','double');
codes = string(C.obstacle_code);  flags = string(C.flag);  flags(ismissing(flags)) = "";
for r = 1:height(C)
    code = strtrim(char(codes(r)));
    if isempty(regexp(code,'^\d\d$','once')), qc.nUnlab = qc.nUnlab + 1; continue; end
    if isKey(repCount, code), repCount(code) = repCount(code) + 1; else, repCount(code) = 1; end
    W = str2double(code(1));  H = str2double(code(2));
    row = r0;
    row.crossing_id   = sprintf('%d_%s_r%d', tn, code, repCount(code));
    row.obstacle_code = code;  row.is_level = 0;
    row.height_class  = sprintf('H%d', H);  row.height_pct_LL = CFG.heightPct(H);
    row.height_cm     = CP.heights_mm(H) / 10;
    row.width_class   = sprintf('W%d', W);  row.width_cm = CFG.width_cm(W);
    row.repeat        = repCount(code);
    ll = pickSide(C.lead_leg(r));  tl = pickSide(C.trail_leg(r));
    tLc = C.lead_cross_s(r) + shift;  tTc = C.trail_cross_s(r) + shift;
    [row, s] = fillCrossing(row, X, ll, tl, tLc, tTc, t, fs, CFG, CP, cpKey, true);
    row.lead_cyc = s.cL;  row.trail_cyc = s.cT;  row.stepchk = stepCheck(X, ll, tl, s.cL, s.cT);
    if strlength(flags(r)) > 0, row.data_quality_flag = 1; end
    [i0, i1] = cycleSpan(X, ll, s.cL);
    if ~isnan(i0)
        row.cam_obstacle_h = robustMed(obsZ(i0:i1)) - CFG.markerR_mm;
        row.cam_obstacle_x = robustMed(obsY(i0:i1));
    end
    row = finishFlags(row);
    rows = [rows, row]; %#ok<AGROW>
    side = [side; sideRows(tn, row, s)]; %#ok<AGROW>
end

[rows, qc.imu] = imuRoles(rows, X, t, fs, CFG);

% ---------------- level walks: the stride at the obstacle location (y = 0) ----------------
[P, qc.lvCand] = levelPasses(X.L, X.R, t, C, shift, CFG);
qc.lvFeatBouts = [runCount(X.L.terr, 'Level_Walk'), runCount(X.R.terr, 'Level_Walk')];
qc.nLevelPass = numel(P);  agree = [];
for p = 1:numel(P)
    if P(p).tL <= P(p).tR, ll = 'L'; tl = 'R'; tLc = P(p).tL; tTc = P(p).tR;
    else,                  ll = 'R'; tl = 'L'; tLc = P(p).tR; tTc = P(p).tL; end
    row = r0;
    row.crossing_id = sprintf('%d_level_p%d', tn, p);
    row.obstacle_code = 'level';  row.is_level = 1;  row.height_class = 'level';
    row.repeat = p;
    [row, s] = fillCrossing(row, X, ll, tl, tLc, tTc, t, fs, CFG, CP, cpKey, false);
    row.lead_cyc = s.cL;  row.trail_cyc = s.cT;
    agree(end+1) = strcmpi(s.L.terr, 'Level_Walk') || strcmpi(s.T.terr, 'Level_Walk'); %#ok<AGROW>
    row = finishFlags(row);
    rows = [rows, row]; %#ok<AGROW>
    side = [side; sideRows(tn, row, s)]; %#ok<AGROW>
end
if ~isempty(agree), qc.lvFeatLogAgree = mean(agree); end

% ---- chronological trial order (level + obstacle, by the lead camera y=0 time) ----
tc = [rows.lead_crossing_t_cam];  [~, ord] = sort(tc);
for k = 1:numel(ord), rows(ord(k)).trial_order = k; end
% ---- foot sign check vs camera foot pitch (per role) ----
fr = cell2mat(side(:,end));  rl = side(:,3);
qc.footSignR = [median(fr(strcmp(rl,'lead')),'omitnan'), median(fr(strcmp(rl,'trail')),'omitnan')];
qc.flip = struct();
for sd = 'LR'
    for q = 1:size(CFG.segs,1)
        S = X.(sd).(CFG.segs{q,1});  if isempty(S), v = NaN; else, v = S.flip; end
        qc.flip.([sd '_' CFG.segs{q,1}]) = v;
    end
end
end

function [row, s] = fillCrossing(row, X, ll, tl, tLc, tTc, t, fs, CFG, CP, cpKey, isObs)
% Both limbs of one crossing (or level pass) -> one row.
s.cL = NaN;  s.cT = NaN;
if ll ~= ' ', [c, ok] = cycleAtTime(X.(ll).zvp, t, tLc); if ok, s.cL = c; end, end
if tl ~= ' ', [c, ok] = cycleAtTime(X.(tl).zvp, t, tTc); if ok, s.cT = c; end, end
s.L = limbFeat(getSide(X,ll), s.cL, tLc, t, fs, CFG, cpEntry(CP,cpKey,ll,s.cL), isObs, 'Leading');
s.T = limbFeat(getSide(X,tl), s.cT, tTc, t, fs, CFG, cpEntry(CP,cpKey,tl,s.cT), isObs, 'Trailing');
row = putLimb(row, 'lead_',  s.L);
row = putLimb(row, 'trail_', s.T);
row.leading_limb = strtrim(ll);
if ll ~= ' ' && ~isempty(row.dominant_leg)
    row.lead_is_dominant = double(upper(row.dominant_leg(1)) == ll);
end
% approach strides (lead limb, the two strides before the crossing stride)
s.app = nan(2,2);
if ~isnan(s.cL)
    for k = 1:2, [s.app(k,1), s.app(k,2)] = strideAt(X.(ll), s.cL - k, fs, CFG); end
end
row.stride_len_app1 = s.app(1,1);  row.stride_len_app2 = s.app(2,1);
g = isfinite(s.app(:,1));
if any(g), row.speed_approach = sum(s.app(g,1))/1000 / sum(s.app(g,2)); end
if s.L.stride_s > 0 && isfinite(s.L.stride_mm)
    row.speed_cross = (s.L.stride_mm/1000) / s.L.stride_s;
end
if s.L.stride_s > 0, row.cadence = 120 / s.L.stride_s; end
row.cross_duration    = s.T.landing_t - s.L.toeoff_t;
row.lead_trail_lag_ms = (s.T.crossing_t_imu - s.L.crossing_t_imu) * 1000;
row.trajectory_invalid = double(s.L.zhc_invalid || s.T.zhc_invalid);
row.missing_dot    = double(~(s.L.ok_dot   && s.T.ok_dot));
row.missing_camera = double(~(s.L.ok_cam   && s.T.ok_cam));
row.missing_event  = double(~(s.L.ok_event && s.T.ok_event));
roleBad = (isObs && ~isnan(s.cL) && ~strcmp(s.L.role,'Leading')) || ...
          (isObs && ~isnan(s.cT) && ~strcmp(s.T.role,'Trailing'));
longStride = any([s.L.stride_s s.T.stride_s] > CFG.maxStride_s);
row.data_quality_flag = double(roleBad || ~s.L.spans0 || ~s.T.spans0 || longStride);
if isObs
    row.contact_flag = double(any([row.lead_cam_min_clearance row.trail_cam_min_clearance] <= 0));
else
    row.contact_flag = 0;
end
end

function [rows, thr] = driftFlags(rows, CFG)
% zhc_drift_flag = robust cohort outlier of the uncorrected ZHC landing drift.
d = abs([rows.lead_zhc_raw_drift, rows.trail_zhc_raw_drift]);  d = d(isfinite(d));
md = median(d);  thr = md + CFG.driftMadK * 1.4826 * median(abs(d - md));
for i = 1:numel(rows)
    for pre = {'lead_','trail_'}
        v = rows(i).([pre{1} 'zhc_raw_drift']);
        if isfinite(v), rows(i).([pre{1} 'zhc_drift_flag']) = double(abs(v) > thr); end
    end
    rows(i) = finishFlags(rows(i));
end
end

function row = finishFlags(row)
row.include_biomech = double(~row.missing_event && ~row.missing_dot && ~row.data_quality_flag);
drift = (row.lead_zhc_drift_flag == 1) || (row.trail_zhc_drift_flag == 1);
row.include_ml = double(row.include_biomech && ~row.trajectory_invalid && ~drift);
row.include_ml_noflag = double(row.include_biomech && ~row.trajectory_invalid);
end

%% ========================================================================
%  ONE LIMB, ONE STRIDE (ZVP -> ZVP), SWING = toe-off -> heel-strike inside it
%% ========================================================================
function F = limbFeat(Xs, c, tCam, t, fs, CFG, cpE, isObs, expRole)
F = limbTemplate(CFG);
F.crossing_t_cam = tCam;
if isempty(Xs) || isnan(c), return; end
z = Xs.zvp;  if c + 1 > numel(z), return; end
F.ok_cycle = true;
i0 = z(c);  i1 = z(c+1);  F.stride_s = (i1 - i0) / fs;
F.zhc_raw_drift = rawDrift(Xs.accWv, t, i0, i1);
F.terr = cellAt(Xs.terr, c);  F.role = cellAt(Xs.role, c);
if ~isObs, F.role = expRole; end                         % level: role = order over y=0
ito = Xs.toe(find(Xs.toe > i0 & Xs.toe < i1, 1));
ihs = [];  ihp = [];
if ~isempty(ito)
    ihs = Xs.hs(find(Xs.hs > ito & Xs.hs <= i1, 1));
    ihp = Xs.hs(find(Xs.hs < ito, 1, 'last'));
end

% ---- ZHC trajectory of this stride (window-relative, origin = begin-ZVP) ----
P = [];
if ~isempty(Xs.zhc) && c <= size(Xs.zhc,3) && (i1-i0+1) <= size(Xs.zhc,1), P = Xs.zhc(1:i1-i0+1,:,c); end
haveZ = ~isempty(P) && all(isfinite(P(:)));
if haveZ
    u = P(end,1:2) - P(1,1:2);  F.stride_mm = norm(u) * 1000;  if norm(u) > 0, u = u / norm(u); end
    xmm  = (P(:,1:2) - P(1,1:2)) * u' * 1000;            % progression along net stride direction
    hmm  = (P(:,3) - P(1,3)) * 1000;                      % height above begin-ZVP (stance) level
    Vel  = [gradient(P(:,1)) gradient(P(:,2)) gradient(P(:,3))] * fs;   % m/s
    vx   = Vel(:,1:2) * u';  vmag = vecnorm(Vel, 2, 2);
    tc   = t(i0:i1);
    if isfinite(tCam) && tCam >= tc(1) && tCam <= tc(end)
        F.zhc_h_cross = interp1(tc, hmm, tCam);
        F.zhc_v_cross = interp1(tc, vmag, tCam);
    end
    F.zhc_invalid = ~(F.stride_mm >= CFG.zhcStride_mm(1) && F.stride_mm <= CFG.zhcStride_mm(2));
else
    F.zhc_invalid = true;
end

% ---- camera (reference) ----
yb = sampleNear(Xs.toeM, i0, 2, CFG.zvpNearW);  yl = sampleNear(Xs.toeM, i1, 2, CFG.zvpNearW);
zb = sampleNear(Xs.toeM, i0, 3, CFG.zvpNearW);  zz = Xs.toeM(i0:i1, 3);
F.ok_cam = isfinite(yb) && isfinite(yl) && any(isfinite(zz));
if any(isfinite(zz)), F.cam_peak_foot_h = max(zz, [], 'omitnan'); end
if any(isfinite(Xs.heelM(i0:i1,3))), F.cam_heel_peak = max(Xs.heelM(i0:i1,3), [], 'omitnan'); end
if isfinite(yb) && isfinite(yl), F.direction = dirStr(yl - yb); end
F.spans0 = spans0(Xs.toeM(i0:i1,2));
if isObs && ~isempty(cpE)
    F.cam_min_clearance = minClearance(cpE);
    F.cam_takeoff_dist  = cpE.lift_dist;
    F.cam_landing_dist  = cpE.land_dist;
end
if haveZ && isfinite(yb) && isfinite(yl), F.dotcam_place_err = F.stride_mm - (yl - yb); end

% ---- ZVP-cycle ROM (for the SPSS cross-check only, not a column) ----
for q = 1:size(CFG.segs,1)
    S = Xs.(CFG.segs{q,1});
    if ~isempty(S) && c <= size(S.ref,2), F.(['cyc_rom_' CFG.segs{q,1}]) = max(S.ref(:,c)) - min(S.ref(:,c)); end
end

% ---- swing window ----
if isempty(ito) || isempty(ihs) || ihs - ito < 3, return; end
F.ok_event = true;
sw = (ito:ihs)';  ns = numel(sw);  pct = (0:ns-1)' / (ns-1) * 100;
F.toeoff_t = t(ito);  F.landing_t = t(ihs);  F.swing_time = (ihs - ito) / fs;
if ~isempty(ihp) && (ito - ihp) / fs < 3
    F.stance_time = (ito - ihp) / fs;
    F.stance_conf = mean(Xs.still(ihp:ito));
end
okDot = true;
for q = 1:size(CFG.segs,1)
    k = CFG.segs{q,1};  S = Xs.(k);
    if isempty(S), okDot = false; continue; end
    y = S.ang(sw);
    if all(isnan(y)), okDot = false; continue; end
    [mx, imx] = max(y);  [mn, imn] = min(y);
    ref = NaN;  if c <= size(S.ref,2), ref = median(S.ref(1:CFG.refW, c), 'omitnan'); end
    F.([k '_max']) = mx;  F.([k '_min']) = mn;  F.([k '_rom']) = mx - mn;
    F.([k '_t_max']) = pct(imx);  F.([k '_t_min']) = pct(imn);
    F.([k '_max_corr']) = mx - ref;  F.([k '_min_corr']) = mn - ref;
    v = S.av(sw);  [vmx, ivx] = max(v);  [vmn, ivn] = min(v);
    F.([k '_av_max']) = vmx;  F.([k '_av_min']) = vmn;
    F.([k '_av_t_max']) = pct(ivx);  F.([k '_av_t_min']) = pct(ivn);
    F.([k '_av_toeoff']) = S.av(ito);
end
F.ok_dot = okDot;
m = Xs.accW(sw);  kw = max(1, round(CFG.accWinFrac * ns));
if any(isfinite(m))
    F.foot_acc_peak_start = max(m(1:kw), [], 'omitnan');
    F.foot_acc_peak_land  = max(m(end-kw+1:end), [], 'omitnan');
    F.foot_acc_rms_swing  = sqrt(mean(m.^2, 'omitnan'));
end
if haveZ
    rr = sw - i0 + 1;  hsw = hmm(rr);
    [pk, ip] = max(hsw);
    F.zhc_peak_foot_h = pk;  F.zhc_peak_h_t = pct(ip);  F.zhc_peak_h_x = xmm(rr(ip));
    F.crossing_t_imu  = t(sw(ip));
    F.zhc_h_toeoff = hsw(1);
    F.zhc_h_25 = interp1(pct, hsw, 25);  F.zhc_h_50 = interp1(pct, hsw, 50);  F.zhc_h_75 = interp1(pct, hsw, 75);
    F.zhc_x_toeoff = xmm(rr(1));  F.zhc_x_landing = xmm(rr(end));
    F.zhc_h_landing = hsw(end);
    F.zhc_vz_peak = max(Vel(rr,3));  F.zhc_vx_peak = max(vx(rr));
    F.dur_toeoff_to_cross_s  = F.crossing_t_imu - F.toeoff_t;
    F.dur_cross_to_landing_s = F.landing_t - F.crossing_t_imu;
    if isfinite(F.cam_peak_foot_h) && isfinite(zb), F.dotcam_peak_h_err = pk - (F.cam_peak_foot_h - zb); end
    F.zhc_invalid = F.zhc_invalid || ~(pk >= CFG.zhcPeak_mm(1) && pk <= CFG.zhcPeak_mm(2));
end
% ---- v2: literature-style take-off (toe at its own toe-off), toe-geometry fit samples ----
if isObs && ~isempty(cpE)
    F.cam_takeoff_toeoff = -cpE.obs_w/2 - sampleNear(Xs.toeM, ito, 2, CFG.zvpNearW);
end
if haveZ && ~isempty(Xs.foot) && isfinite(zb)
    a0 = median(Xs.foot.ang(i0:min(i0+2, i1)), 'omitnan');      % foot tilt at begin-ZVP (foot flat)
    th = Xs.foot.ang(sw) - a0;                                   % toe-up positive
    F.toefit = [hsw, sind(th), cosd(th) - 1, Xs.toeM(sw,3) - zb];  % sensor rise, rotation terms, camera toe rise
end
% swing curves (exported to the curves file): signal blocks of CFG.curveN points, 0-100 % swing
pq = linspace(0, 100, CFG.curveN)';  cv = nan(CFG.curveN, numel(CFG.curveSig));
for q = 1:size(CFG.segs,1)
    S = Xs.(CFG.segs{q,1});
    if ~isempty(S), cv(:,q) = interp1(pct, S.ang(sw), pq); end
end
cv(:,4) = interp1(pct, m, pq);
if haveZ, cv(:,5) = interp1(pct, hsw, pq);  cv(:,6) = interp1(pct, xmm(rr), pq); end
F.curve = cv(:)';
% foot sign check: Dot foot tilt vs camera foot pitch (toe-up positive when walking +y)
S = Xs.foot;
if ~isempty(S)
    pitch = atan2d(Xs.toeM(sw,3) - Xs.heelM(sw,3), Xs.toeM(sw,2) - Xs.heelM(sw,2));
    a = S.ang(sw);  g = isfinite(a) & isfinite(pitch);
    if nnz(g) >= 10, cc = corrcoef(a(g), pitch(g)); F.footSignR = cc(1,2); end
end
end

function F = limbTemplate(CFG)
keys = limbKeys(CFG);
F = struct();
for k = 1:numel(keys), F.(keys{k}) = NaN; end
F.ok_cycle = false;  F.ok_event = false;  F.ok_dot = false;  F.ok_cam = false;
F.zhc_invalid = false;  F.spans0 = true;  F.terr = '';  F.role = '';  F.direction = '';
F.stride_mm = NaN;  F.stride_s = NaN;  F.footSignR = NaN;  F.zhc_raw_drift = NaN;  F.toefit = [];  F.cam_heel_peak = NaN;
F.curve = nan(1, CFG.curveN * numel(CFG.curveSig));
for q = 1:size(CFG.segs,1), F.(['cyc_rom_' CFG.segs{q,1}]) = NaN; end
end

function keys = limbKeys(CFG)
% Column suffixes that exist once per limb (prefix lead_ / trail_).
keys = {'toeoff_t','landing_t','crossing_t_imu','crossing_t_cam','dur_toeoff_to_cross_s','dur_cross_to_landing_s'};
for q = 1:size(CFG.segs,1)
    k = CFG.segs{q,1};
    keys = [keys, strcat(k, {'_max','_min','_rom','_t_max','_t_min','_max_corr','_min_corr'})]; %#ok<AGROW>
end
for q = 1:size(CFG.segs,1)
    k = CFG.segs{q,1};
    keys = [keys, strcat(k, {'_av_max','_av_min','_av_t_max','_av_t_min','_av_toeoff'})]; %#ok<AGROW>
end
keys = [keys, {'foot_acc_peak_start','foot_acc_peak_land','foot_acc_rms_swing', ...
    'cross_step_len','swing_time','stance_time', ...
    'zhc_peak_toe_h','zhc_peak_foot_h','zhc_peak_h_t','zhc_peak_h_x','zhc_h_toeoff','zhc_h_25', ...
    'zhc_h_50','zhc_h_75','zhc_h_cross','zhc_x_toeoff','zhc_x_landing','zhc_vz_peak','zhc_vx_peak', ...
    'zhc_v_cross','zhc_h_landing','zhc_drift_flag','stance_conf','dotcam_peak_h_err', ...
    'dotcam_place_err','cam_min_clearance','cam_takeoff_dist','cam_landing_dist','cam_peak_foot_h', ...
    'dotcam_toe_peak_err','cam_takeoff_toeoff'}];
end

function row = putLimb(row, pre, F)
fn = fieldnames(F);
for k = 1:numel(fn)
    nm = [pre fn{k}];
    if isfield(row, nm), row.(nm) = F.(fn{k}); end
end
end

function [len, dur] = strideAt(Xs, k, fs, CFG)
% ZHC net horizontal displacement (mm) and duration (s) of stride k, if it is a
% plausible walking stride (approach strides; else NaN).
len = NaN;  dur = NaN;
z = Xs.zvp;
if k < 1 || k + 1 > numel(z) || isempty(Xs.zhc) || k > size(Xs.zhc,3), return; end
L = z(k+1) - z(k) + 1;  if L > size(Xs.zhc,1), return; end
P = Xs.zhc(1:L,:,k);  if ~all(isfinite(P(:))), return; end
d = (z(k+1) - z(k)) / fs;  l = norm(P(end,1:2) - P(1,1:2)) * 1000;
if d <= CFG.appMaxDur_s && l >= CFG.appMinLen_mm, len = l; dur = d; end
end

%% ========================================================================
%  LEVEL PASSES
%% ========================================================================
function [P, nCand] = levelPasses(XL, XR, t, C, shift, CFG)
% Level walks = passes where both toes cross the obstacle line (camera y = 0)
% moving +y, outside the LABELLED obstacle passes and before the first of them
% (the protocol walks level first; the crossings file lists those level passes as
% unlabelled rows, and the unlabelled rows at the end are the stop gesture).
lab = ~cellfun(@isempty, regexp(strtrim(string(C.obstacle_code)), '^\d\d$', 'once'));
ex = [C.begin_s(lab), C.end_s(lab)] + shift;
ex(:,1) = ex(:,1) - CFG.lvPad_s;  ex(:,2) = ex(:,2) + CFG.lvPad_s;
tFirst = min(ex(:,1));
eL = upCross(XL.toeM(:,2), t, ex, CFG);  eR = upCross(XR.toeM(:,2), t, ex, CFG);
eL = eL(eL < tFirst);  eR = eR(eR < tFirst);
nCand = [numel(eL) numel(eR)];                % single-foot y=0 crossings before the first obstacle
P = struct('tL',{},'tR',{});  used = false(size(eR));
for i = 1:numel(eL)
    d = abs(eR - eL(i));  d(used) = inf;
    [m, j] = min(d);
    if isempty(m) || m > CFG.lvPairTol_s, continue; end
    used(j) = true;  P(end+1) = struct('tL', eL(i), 'tR', eR(j)); %#ok<AGROW>
end
end

function ev = upCross(y, t, ex, CFG)
ev = [];  vel = [];
k = find(y(1:end-1) < 0 & y(2:end) >= 0 & isfinite(y(1:end-1)) & isfinite(y(2:end)));
for i = k(:)'
    tc = t(i) + (0 - y(i)) / (y(i+1) - y(i)) * (t(i+1) - t(i));
    if any(tc >= ex(:,1) & tc <= ex(:,2)), continue; end
    a = max(1, i-6);  b = min(numel(y), i+7);
    if ~(isfinite(y(a)) && isfinite(y(b)) && y(b) - y(a) > CFG.lvMinRise_mm), continue; end
    v = (y(b) - y(a)) / (t(b) - t(a));
    if ~isempty(ev) && tc - ev(end) < CFG.lvDedup_s
        if v > vel(end), ev(end) = tc; vel(end) = v; end
        continue;
    end
    ev(end+1) = tc;  vel(end+1) = v; %#ok<AGROW>
end
end

%% ========================================================================
%  CLEANING + LOGS
%% ========================================================================
function [T, xlog] = applyCleaning(T, CL)
% 3*MAD gate on the thigh angle values per participant x obstacle code x role (step 9's
% rule: >= 4 values, drop |x - median| > madK*1.4826*MAD). CL.test = the participants
% gated (dataset: Test 106 only; sensitivity log: everyone). Gated values -> NaN here,
% the original is kept in the log.
xlog = cell(0,7);
for s = 1:numel(CL)
    cs = CL(s);
    for tn = cs.test(:)'
    sel = T.participant_id == tn & T.is_level == 0;
    ucodes = unique(T.obstacle_code(sel));
    for u = 1:numel(ucodes)
        idx = find(sel & strcmp(T.obstacle_code, ucodes{u}));
        for pre = {'lead_','trail_'}
            for v = cs.vars
                col = [pre{1} v{1}];  x = T.(col)(idx);  g = isfinite(x);
                if nnz(g) < 4, continue; end
                md = median(x(g));  ad = median(abs(x(g) - md));
                if ad <= 0, continue; end
                bad = g & abs(x - md) > cs.madK * 1.4826 * ad;
                for b = find(bad)'
                    i = idx(b);
                    xlog(end+1,:) = {tn, T.crossing_id{i}, col, x(b), NaN, 'cleaned', ...
                        sprintf('Test %d thigh MAD gate: > %g*MAD from the %s %s median (%.2f) -> NaN', ...
                        tn, cs.madK, ucodes{u}, strip(pre{1},'_'), md)}; %#ok<AGROW>
                    T.(col)(i) = NaN;
                    if isempty(T.cleaned_variables{i}), T.cleaned_variables{i} = col;
                    else, T.cleaned_variables{i} = [T.cleaned_variables{i} ';' col]; end
                end
            end
        end
    end
    end
end
end

function xlog = missingLog(T, SPEC)
% One line per empty FEATURE / REFERENCE / TARGET cell; one 'ALL' line for a column
% that could not be computed for anyone. Level-walk cells of obstacle-only columns are
% not applicable (no obstacle) and are not logged.
xlog = cell(0,7);
obsOnly = obstacleOnlyCols();
for k = 1:size(SPEC,1)
    nm = SPEC{k,1};  role = SPEC{k,2};
    if ~any(contains(role, {'FEATURE','REFERENCE','TARGET'})) || ~isnumeric(T.(nm)), continue; end
    x = T.(nm);
    if all(isnan(x))
        xlog(end+1,:) = {'ALL', 'ALL', nm, NaN, NaN, 'not computed', SPEC{k,4}}; %#ok<AGROW>
        continue;
    end
    for i = find(isnan(x))'
        if T.is_level(i) == 1 && any(endsWith(nm, obsOnly)), continue; end
        if contains(T.cleaned_variables{i}, nm), continue; end            % already logged as cleaned
        xlog(end+1,:) = {T.participant_id(i), T.crossing_id{i}, nm, NaN, NaN, 'missing', missingReason(T(i,:), nm)}; %#ok<AGROW>
    end
end
end

function why = missingReason(R, nm)
lim = 'lead';  if startsWith(nm,'trail_'), lim = 'trail'; end
if R.missing_event == 1 && isnan(R.([lim '_toeoff_t']))
    why = sprintf('%s limb: no ZVP cycle or no toe-off/heel-strike inside it', lim);
elseif contains(nm,'cam_') && R.missing_camera == 1
    why = 'camera marker data missing at the needed frames (occlusion)';
elseif contains(nm,'_app')
    why = 'approach stride not a plausible walking stride (turn/pause, > 2 s or < 300 mm) or missing ZHC';
elseif contains(nm,'zhc_') || contains(nm,'speed') || contains(nm,'dotcam')
    why = 'ZHC trajectory missing/invalid for the stride, or camera crossing time outside the stride';
elseif R.missing_dot == 1
    why = 'Dot segment signal missing in the swing window';
else
    why = 'not computable for this row (see data_dictionary.md)';
end
end

%% ========================================================================
%  OUTPUT WRITERS
%% ========================================================================
function writeCsv(f, T, textCols, dec)
fid = fopen(f, 'w');  assert(fid > 0, 'cannot open %s (open in Excel?)', f);
c = onCleanup(@() fclose(fid));
nm = T.Properties.VariableNames;
fprintf(fid, '%s\n', strjoin(nm, ','));
cols = cell(height(T), numel(nm));
for j = 1:numel(nm)
    x = T.(nm{j});
    if any(strcmp(nm{j}, textCols)) || iscell(x)
        cols(:,j) = cellfun(@csvText, x, 'UniformOutput', false);
    else
        cols(:,j) = arrayfun(@(v) numText(v, dec), x, 'UniformOutput', false);
    end
end
for i = 1:height(T), fprintf(fid, '%s\n', strjoin(cols(i,:), ',')); end
end

function s = numText(v, dec)
if isnan(v), s = ''; else, s = sprintf('%.10g', round(v, dec)); end
end

function s = csvText(v)
s = char(string(v));  if ismissing(string(v)), s = ''; end
if contains(s, {',','"'}), s = ['"' strrep(s,'"','""') '"']; end
end

function writeLog(f, xlog)
fid = fopen(f, 'w');  assert(fid > 0, 'cannot open %s', f);
c = onCleanup(@() fclose(fid));
fprintf(fid, 'participant_id,crossing_id,variable,original_value,cleaned_value,action,reason\n');
for i = 1:size(xlog,1)
    p = xlog{i,1};  if isnumeric(p), p = num2str(p); end
    fprintf(fid, '%s,%s,%s,%s,%s,%s,%s\n', p, xlog{i,2}, xlog{i,3}, numText(xlog{i,4},4), ...
        numText(xlog{i,5},4), xlog{i,6}, csvText(xlog{i,7}));
end
end

%% ========================================================================
%  HELPERS (copied from the pipeline so the definitions are identical)
%% ========================================================================
function [c, ok] = cycleAtTime(zvp, tt, T)
% step 7: which ZVP stride contains IMU time T.
c = NaN;  ok = false;
if numel(zvp) < 2 || isnan(T), return; end
tb = tt(zvp);  tb = tb(:);
if T < tb(1) || T > tb(end), return; end
c = find(tb(1:end-1) <= T & T < tb(2:end), 1);
if isempty(c)
    if T == tb(end), c = numel(tb) - 1; else, return; end
end
ok = true;
end

function v = sampleNear(M, idx, col, W)
% step 8: value at M(idx,col); if NaN, nearest finite within +/- W frames.
n = size(M,1);  v = NaN;
if idx < 1 || idx > n, return; end
v = M(idx,col);  if ~isnan(v), return; end
for d = 1:W
    if idx-d >= 1 && ~isnan(M(idx-d,col)), v = M(idx-d,col); return; end
    if idx+d <= n && ~isnan(M(idx+d,col)), v = M(idx+d,col); return; end
end
v = NaN;
end

function v = minClearance(c)
% step 9: min(foot z while |y| <= w/2, incl. the y=0 toe/heel heights) - obstacle top.
w = c.obs_w;  h = c.obs_h;  a = c.arc;
inT = abs(a.yToe) <= w/2;  inH = abs(a.yHeel) <= w/2;
zs = [a.zToe(inT); a.zHeel(inH); c.z_toe_cross; c.z_heel_cross];
zs = zs(~isnan(zs));
if isempty(zs), v = NaN; else, v = min(zs) - h; end
end

function m = robustMed(v)
% step 8: median after rejecting samples > 3 robust SD from the median.
v = v(~isnan(v));
if isempty(v), m = NaN; return; end
md = median(v);  ad = median(abs(v - md));
if ad > 0
    keep = abs(v - md) <= 3*1.4826*ad;
    if any(keep), v = v(keep); end
end
m = median(v);
end

function [m, W] = worldAccMag(q, acc, g)
% |a| in the global frame, gravity removed (W = the N x 3 vector). Same rotation
% as the step-4 ZHC: eul = quat2eul(q,'ZYX'), R = Rz(yaw)*Ry(pitch)*Rx(roll),
% a_w = R*a - [0 0 g].
e = quat2eul(q, 'ZYX');  yw = e(:,1);  p = e(:,2);  r = e(:,3);
cr = cos(r); sr = sin(r); cp = cos(p); sp = sin(p); cy = cos(yw); sy = sin(yw);
ax = acc(:,1);  ay = acc(:,2);  az = acc(:,3);
wx = cy.*cp.*ax + (cy.*sp.*sr - sy.*cr).*ay + (cy.*sp.*cr + sy.*sr).*az;
wy = sy.*cp.*ax + (sy.*sp.*sr + cy.*cr).*ay + (sy.*sp.*cr - cy.*sr).*az;
wz = -sp.*ax + cp.*sr.*ay + cp.*cr.*az - g;
m = sqrt(wx.^2 + wy.^2 + wz.^2);
W = [wx wy wz];
end

function dz = rawDrift(W, t, i0, i1)
% Vertical position at the end-ZVP from the step-4 ZHC FIRST integration (no bias
% removed), mm: the landing-height error that the level-ground bias solve removes.
dtv = diff(t(i0:i1));  A = W(i0:i1-1, :);
if any(~isfinite(A(:))), dz = NaN; return; end
v  = [zeros(1,3); cumsum(A .* dtv, 1)];
pz = sum(v(1:end-1,3) .* dtv + 0.5 * A(:,3) .* dtv.^2);
dz = pz * 1000;
end

function o = obstacleMean(Cam, col)
m = {};
for nm = {'obstacle1','obstacle2'}
    if isfield(Cam.markers, nm{1}), m{end+1} = Cam.markers.(nm{1})(:,col); end %#ok<AGROW>
end
if isempty(m), o = nan(numel(Cam.time),1); else, o = mean(cat(2, m{:}), 2, 'omitnan'); end
end

function tf = spans0(y)
y = y(isfinite(y));  tf = true;
if numel(y) >= 2, tf = min(y) < 0 && max(y) > 0; end
end

function [i0, i1] = cycleSpan(X, sd, c)
i0 = NaN;  i1 = NaN;
if sd == ' ' || isnan(c), return; end
i0 = X.(sd).zvp(c);  i1 = X.(sd).zvp(c+1);
end

function e = cpEntry(CP, cpKey, sd, c)
e = [];
if sd == ' ' || isnan(c), return; end
k = sprintf('%s%d', sd, c);
if isKey(cpKey, k), e = CP.crossing(cpKey(k)); end
end

function Xs = getSide(X, sd)
if sd == ' ', Xs = []; else, Xs = X.(sd); end
end

function s = pickSide(v)
s = upper(strtrim(char(string(v))));
if isempty(s) || ~(s(1)=='L' || s(1)=='R'), s = ' '; else, s = s(1); end
end

function w = sideWord(sd)
if sd == 'R', w = 'Right'; else, w = 'Left'; end
end

function s = dirStr(dy)
if dy > 0, s = '+y'; elseif dy < 0, s = '-y'; else, s = ''; end
end

function v = cellAt(c, k)
v = '';  if iscell(c) && k <= numel(c) && ischar(c{k}), v = c{k}; end
end

function r = emptyRow(names, textCols)
r = struct();
for k = 1:numel(names)
    if any(strcmp(names{k}, textCols)), r.(names{k}) = ''; else, r.(names{k}) = NaN; end
end
end

function s = sideRows(tn, row, S)
% Per-limb side table for the checks: tn, id, role, terrain code, stride mm, stride s,
% ZVP-cycle ROM thigh/shank/foot, foot sign r.
s = {};
L = {'lead', S.L; 'trail', S.T};
for k = 1:2
    F = L{k,2};
    s(end+1,:) = {tn, row.crossing_id, L{k,1}, row.obstacle_code, F.stride_mm, F.stride_s, ...
        F.cyc_rom_thigh, F.cyc_rom_shank, F.cyc_rom_foot, F.zhc_raw_drift, F.footSignR}; %#ok<AGROW>
end
end

%% ========================================================================
%  PARTICIPANT META
%% ========================================================================
function meta = loadMeta(f, tests, root)
% participants_meta.csv is filled BY HAND. On first run a template is written with
% only what the lab files actually state (sex from the PKMAS header, leg length if
% step 8 was given one); everything else blank. Existing files are never overwritten.
if ~isfile(f)
    id = tests(:);  n = numel(id);
    sex = strings(n,1);  ll = nan(n,1);
    for i = 1:n
        sex(i) = pkmasGender(root, id(i));
        cpf = fullfile(root,'Results','Parameters Output',sprintf('Test %d',id(i)),sprintf('CrossingParams_Test%d.mat',id(i)));
        if isfile(cpf)
            d = load(cpf,'CP');
            if isfield(d.CP,'legLen_cm') && isfinite(d.CP.legLen_cm), ll(i) = d.CP.legLen_cm; end
        end
    end
    M = table(id, nan(n,1), sex, strings(n,1), nan(n,1), ll, nan(n,1), strings(n,1), ...
        'VariableNames', {'participant_id','age_y','sex','dominant_leg','body_height_cm', ...
        'leg_length_cm','mass_kg','order_randomized'});
    writetable(M, f);
    fprintf('Created participant template %s - fill it in and re-run.\n', f);
end
meta = readtable(f, 'TextType','string', 'Delimiter',',');
for v = {'sex','dominant_leg','order_randomized'}
    if ~isstring(meta.(v{1})), meta.(v{1}) = string(meta.(v{1})); end
    meta.(v{1})(ismissing(meta.(v{1}))) = "";
end
end

function g = pkmasGender(root, tn)
g = "";
d = dir(fullfile(root,'Data','Pkmas',sprintf('test%d',tn),'*.txt'));
for k = 1:numel(d)
    fid = fopen(fullfile(d(k).folder, d(k).name), 'r');  if fid < 0, continue; end
    for i = 1:12
        ln = fgetl(fid);  if ~ischar(ln), break; end
        tok = regexp(ln, '^\W*Gender;\s*(\w+)', 'tokens', 'once');
        if ~isempty(tok), g = string(tok{1}); break; end
    end
    fclose(fid);
    if g ~= "", return; end
end
end

%% ========================================================================
%  COLUMN SPEC  {name, role, unit, definition, sign convention, source}
%% ========================================================================
function S = columnSpec()
S = cell(0,6);
add = @(S, n, r, u, d, sg, src) [S; {n, r, u, d, sg, src}];
B = 'build_crossing_master.m';
% ---- 1. ID ----
S = add(S,'crossing_id','ID','-','<participant>_<obstacle_code>_r<repeat> (obstacle) or <participant>_level_p<pass> (level walk). Unique.','-',B);
S = add(S,'participant_id','ID','-','Participant = Test number (101-110).','-',B);
% ---- 2. Design & labels ----
S = add(S,'obstacle_code','LABEL','-','Two-digit obstacle code [width][height] from the camera crossings file (e.g. 22 = W2_H2); "level" for level walks.','-','testN_crossings.xlsx');
S = add(S,'is_level','LABEL','0/1','1 = level walk (no obstacle), 0 = obstacle crossing.','-',B);
S = add(S,'height_class','LABEL','-','H1/H2/H3 from obstacle_code; "level" for level walks.','-','obstacle_code');
S = add(S,'height_pct_LL','LABEL','% leg length','Nominal design height: H1/H2/H3 = 10/20/30% of leg length. Empty for level.','-','design');
S = add(S,'height_cm','LABEL','cm','Obstacle height used by step 8 for clearance: AUTO = robust median of the obstacle markers per H-level - 2.0 cm marker radius (Tests 103-110); Tests 101-102 = 10/20/30% of the leg length typed into step 8.','-','CrossingParams_TestN.mat (CP.heights_mm)');
S = add(S,'width_class','LABEL','-','W1/W2 from obstacle_code; empty for level.','-','obstacle_code');
S = add(S,'width_cm','LABEL','cm','W1 = 5 cm, W2 = 15 cm (fixed). Empty for level.','-','design');
S = add(S,'repeat','META','-','Repeat number of this obstacle within the participant (1..5; 6 where an extra pass was labelled), or level pass number.','-',B);
S = add(S,'trial_order','META','-','Chronological rank of this row within the participant (level + obstacle), by the lead limb camera y=0 time.','-',B);
S = add(S,'order_randomized','META','-','From participants_meta.csv (hand-entered). The data show obstacles run in blocks of ~5 repeats whose block order differs between participants.','-','participants_meta.csv');
S = add(S,'leading_limb','META','L/R','Physical side of the leading limb (first over the obstacle). Obstacle rows: lead_leg from the camera crossings file (the Dot Logger has no leading-leg lines for Tests 101-110; step 7 uses the same camera source). Level rows: the foot whose toe crosses y=0 first.','-','testN_crossings.xlsx / camera');
S = add(S,'lead_is_dominant','META','0/1','1 if leading_limb equals dominant_leg (participants_meta.csv); empty if dominance unknown.','-','participants_meta.csv');
% ---- 3. Participant ----
S = add(S,'age_y','META','years','Age (participants_meta.csv; reporting only).','-','participants_meta.csv');
S = add(S,'sex','META','-','Sex (participants_meta.csv, from the lab measurement sheet).','-','participants_meta.csv');
S = add(S,'dominant_leg','META','L/R','Dominant leg (participants_meta.csv).','-','participants_meta.csv');
S = add(S,'body_height_cm','META','cm','Body height (participants_meta.csv).','-','participants_meta.csv');
S = add(S,'leg_length_cm','META','cm','Leg length (participants_meta.csv; pre-filled only where step 8 stored one).','-','participants_meta.csv');
S = add(S,'mass_kg','META','kg','Body mass (participants_meta.csv).','-','participants_meta.csv');
% ---- 4. Events & timing ----
for L = {'lead','trail'}
    l = L{1};
    S = add(S,[l '_toeoff_t'],'META','s','Toe-off of this limb inside its crossing stride (step 4: inverted minimum of the Dot foot roll angle, first one after the begin-ZVP). Seconds from trial start (Dot clock).','-','SegmentedParams_TestN.mat (Seg.toeL/R)');
    S = add(S,[l '_landing_t'],'META','s','Heel-strike (landing) of this limb after its toe-off, before the end-ZVP (step 4: maximum of the foot roll angle between toe-offs). Seconds from trial start.','-','SegmentedParams_TestN.mat (Seg.hsL/R)');
end
for L = {'lead','trail'}
    l = L{1};
    S = add(S,[l '_crossing_t_imu'],'META','s','Wearable crossing instant = time of the ZHC peak foot height in the swing (step 9 "foot apex = clearing the obstacle").',  '-',B);
end
for L = {'lead','trail'}
    l = L{1};
    S = add(S,[l '_crossing_t_cam'],'REFERENCE','s','Camera crossing instant: the toe passes y=0 (obstacle centre). Obstacle rows: lead/trail_cross_s from the crossings file + sync shift; level rows: detected y=0 crossing. Dot clock.','-','testN_crossings.xlsx + CameraSynced');
end
S = add(S,'dot_cam_sync_offset_s','META','s','Camera->Dot clock shift (t_dot = t_cam + offset). Step 5: 3x left-leg raise; camera L_toe vertical-velocity peaks matched to the Left Foot (Dot) peaks; residual drift ~1 ms.','-','CameraSynced_TestN.mat (Cam.sync.shift_s)');
for L = {'lead','trail'}
    l = L{1};
    S = add(S,[l '_dur_toeoff_to_cross_s'],'META','s','crossing_t_imu - toeoff_t.','-',B);
    S = add(S,[l '_dur_cross_to_landing_s'],'META','s','landing_t - crossing_t_imu.','-',B);
end
S = add(S,'lead_trail_lag_ms','META','ms','(trail_crossing_t_imu - lead_crossing_t_imu) x 1000.','-',B);
% ---- 5. Tier 1 segment angles ----
sgn = struct('thigh','sign-normalized (step 9): max = forward tilt (thigh flexion), min = backward tilt', ...
             'shank','sign-normalized (step 9): max = forward (reach), min = backward (heel-up)', ...
             'foot', 'sign-normalized (step 9): max = toe-up, min = toe-down');
for L = {'lead','trail'}
    l = L{1};
    for k = {'thigh','shank','foot'}
        s = k{1};  src = sprintf('AllData_TestN.mat (%s Dot euler X) + signTemplates.mat', s);
        S = add(S,sprintf('%s_%s_max',l,s),'FEATURE','deg',sprintf('Max %s sagittal tilt in the swing (toe-off -> heel-strike).',s),sgn.(s),src);
        S = add(S,sprintf('%s_%s_min',l,s),'FEATURE','deg',sprintf('Min %s sagittal tilt in the swing.',s),sgn.(s),src);
        S = add(S,sprintf('%s_%s_rom',l,s),'FEATURE','deg','max - min in the swing (sign-invariant). NOTE: the SPSS/step 9 ROM is over the whole ZVP->ZVP stride, so it is larger.','-',src);
        S = add(S,sprintf('%s_%s_t_max',l,s),'FEATURE','% swing','Time of the max, % of swing (0 = toe-off, 100 = heel-strike).','-',src);
        S = add(S,sprintf('%s_%s_t_min',l,s),'FEATURE','% swing','Time of the min, % of swing.','-',src);
        S = add(S,sprintf('%s_%s_max_corr',l,s),'FEATURE','deg','max - neutral; neutral = this stride''s begin-ZVP angle (median of the first 4 of 200 normalized samples, as step 9 peak excursions). The raw _max is NOT offset-corrected.',sgn.(s),src);
        S = add(S,sprintf('%s_%s_min_corr',l,s),'FEATURE','deg','min - neutral (same neutral).',sgn.(s),src);
    end
end
% ---- 6. Tier 1b dynamics ----
for L = {'lead','trail'}
    l = L{1};
    for k = {'thigh','shank','foot'}
        s = k{1};  src = sprintf('AllData_TestN.mat (%s Dot euler X)', s);
        S = add(S,sprintf('%s_%s_av_max',l,s),'FEATURE','deg/s',sprintf('Max sagittal angular velocity of the %s in the swing = d/dt of the sign-normalized tilt (central difference, 60 Hz).',s),['positive = rotating towards the angle''s max (' sgn.(s) ')'],src);
        S = add(S,sprintf('%s_%s_av_min',l,s),'FEATURE','deg/s','Min sagittal angular velocity in the swing.','same as _av_max',src);
        S = add(S,sprintf('%s_%s_av_t_max',l,s),'FEATURE','% swing','Time of av max, % swing.','-',src);
        S = add(S,sprintf('%s_%s_av_t_min',l,s),'FEATURE','% swing','Time of av min, % swing.','-',src);
        S = add(S,sprintf('%s_%s_av_toeoff',l,s),'FEATURE','deg/s','Angular velocity at toe-off.','same as _av_max',src);
    end
end
for L = {'lead','trail'}
    l = L{1};  src = 'AllData_TestN.mat (Foot Dot acc + quaternion)';
    S = add(S,[l '_foot_acc_peak_start'],'FEATURE','m/s2','Peak |foot acceleration| in the FIRST 25% of the swing (near swing initiation). Global frame (step-4 ZHC rotation), gravity removed, resultant magnitude.','magnitude (>= 0)',src);
    S = add(S,[l '_foot_acc_peak_land'],'FEATURE','m/s2','Peak |foot acceleration| in the LAST 25% of the swing (near landing).','magnitude (>= 0)',src);
    S = add(S,[l '_foot_acc_rms_swing'],'FEATURE','m/s2','RMS of |foot acceleration| over the swing.','magnitude (>= 0)',src);
end
% ---- 7. Tier 2 gait & ZHC ----
zsrc = 'SegmentedParams_TestN.mat (Seg.zhc posTime)';
S = add(S,'stride_len_app1','FEATURE','mm','Lead limb ZHC stride length (net horizontal displacement ZVP->ZVP) of the stride just BEFORE the crossing stride. Empty if not a walking stride (> 2 s or < 300 mm).','-',zsrc);
S = add(S,'stride_len_app2','FEATURE','mm','Same, two strides before the crossing stride.','-',zsrc);
S = add(S,'lead_cross_step_len','FEATURE','mm','NOT COMPUTED: a step length needs the vector between the two feet. The per-stride ZHC has no common origin, and the continuous ZHC (Seg.zhc pZvp, both feet in the Dot global frame) drifts by metres over a trial: Dot vs camera step length r ~ 0 (build_report.md, task 10). Left empty.','-','-');
S = add(S,'trail_cross_step_len','FEATURE','mm','NOT COMPUTED (see lead_cross_step_len).','-','-');
S = add(S,'speed_approach','FEATURE','m/s','(stride_len_app1 + app2) / (their durations), lead limb.','-',zsrc);
S = add(S,'speed_cross','FEATURE','m/s','Lead crossing stride: ZHC stride length / ZVP->ZVP duration (step 9 speed).','-',zsrc);
S = add(S,'cadence','FEATURE','steps/min','120 / lead crossing stride duration (step 9 cadence).','-',B);
S = add(S,'lead_swing_time','FEATURE','s','Lead heel-strike - toe-off.','-',B);
S = add(S,'trail_swing_time','FEATURE','s','Trail heel-strike - toe-off.','-',B);
S = add(S,'lead_stance_time','FEATURE','s','Lead stance before the crossing swing: toe-off - previous heel-strike of the same foot.','-',B);
S = add(S,'trail_stance_time','FEATURE','s','Trail stance before its crossing swing.','-',B);
S = add(S,'cross_duration','FEATURE','s','Whole crossing: trail landing_t - lead toeoff_t.','-',B);
zfr = 'ZHC frame: Dot global frame (z up, gravity), origin = the foot sensor at the stride''s begin-ZVP; x = progression along the stride''s net horizontal displacement.';
for L = {'lead','trail'}
    l = L{1};
    S = add(S,[l '_zhc_peak_toe_h'],'FEATURE','mm',['Peak toe height in the swing above its begin-ZVP height, from the foot sensor by a rigid-body transform (Sharafian Moghaddam & Hejrati 2026): ' ...
        'toe rise = sensor rise (ZHC z) + rx*sin(theta) + rz*(cos(theta)-1), theta = Dot foot tilt - its begin-ZVP value (toe-up positive), [rx rz] = fixed sensor-to-toe-marker vector in the foot frame. ' ...
        'The vector is NOT measured: it is fitted by least squares to the camera toe-marker rise of the OTHER participants (leave-one-participant-out), so no camera data of this participant are used. Per-participant fits in build_report.md.'],'up positive',[zsrc ' + Dot foot tilt']);
    S = add(S,[l '_zhc_peak_foot_h'],'FEATURE','mm',['Peak foot-sensor height in the swing, above its begin-ZVP (stance) height. ' zfr],'up positive',zsrc);
    S = add(S,[l '_zhc_peak_h_t'],'FEATURE','% swing','Time of the peak height, % swing.','-',zsrc);
    S = add(S,[l '_zhc_peak_h_x'],'FEATURE','mm','Progression x at the peak height (from begin-ZVP).','forward positive',zsrc);
    S = add(S,[l '_zhc_h_toeoff'],'FEATURE','mm','Height at toe-off.','up positive',zsrc);
    S = add(S,[l '_zhc_h_25'],'FEATURE','mm','Height at 25% swing.','up positive',zsrc);
    S = add(S,[l '_zhc_h_50'],'FEATURE','mm','Height at 50% swing.','up positive',zsrc);
    S = add(S,[l '_zhc_h_75'],'FEATURE','mm','Height at 75% swing.','up positive',zsrc);
    S = add(S,[l '_zhc_h_cross'],'REFERENCE','mm','ZHC height at the CAMERA crossing instant (crossing_t_cam). Uses camera timing -> REFERENCE, not a feature.','up positive',[zsrc ' + camera time']);
    S = add(S,[l '_zhc_x_toeoff'],'FEATURE','mm','Progression x at toe-off.','forward positive',zsrc);
    S = add(S,[l '_zhc_x_landing'],'FEATURE','mm','Progression x at heel-strike.','forward positive',zsrc);
    S = add(S,[l '_zhc_vz_peak'],'FEATURE','m/s','Peak vertical velocity in the swing (d/dt ZHC z).','up positive',zsrc);
    S = add(S,[l '_zhc_vx_peak'],'FEATURE','m/s','Peak progression velocity in the swing.','forward positive',zsrc);
    S = add(S,[l '_zhc_v_cross'],'REFERENCE','m/s','|ZHC velocity| at the CAMERA crossing instant -> REFERENCE (camera timing).','magnitude',[zsrc ' + camera time']);
end
% ---- 8. ZHC quality & sync ----
for L = {'lead','trail'}
    l = L{1};
    S = add(S,[l '_zhc_h_landing'],'FLAG','mm','ZHC foot-sensor height at heel-strike, above its begin-ZVP height. NOT a drift measure by itself: the heel is on the floor at the trailing heel-strike (camera), but the sensor sits on the dorsum and the foot is pitched toe-up, so ~50-100 mm is normal. (At the end-ZVP the ZHC level-ground bias solve forces the height to exactly 0.)','up positive',zsrc);
end
for L = {'lead','trail'}
    S = add(S,[L{1} '_zhc_drift_flag'],'FLAG','0/1','Landing-height drift flag: 1 if |uncorrected ZHC landing height| (end-ZVP height from the step-4 first integration, before the level-ground bias solve removes it) > cohort median + 3*1.4826*MAD (threshold printed in build_report.md).','-',B);
end
for L = {'lead','trail'}
    S = add(S,[L{1} '_stance_conf'],'FLAG','0-1','Fraction of the stance before the swing (previous heel-strike -> toe-off) that meets the step-4 still-foot rule (|gyro| < 24 and |acc| < 21).','-',B);
end
S = add(S,'trajectory_invalid','FLAG','0/1','1 if either limb''s ZHC stride is missing/non-finite, its stride length is outside 200-2500 mm, or its peak height outside 10-800 mm.','-',B);
for L = {'lead','trail'}
    S = add(S,[L{1} '_dotcam_peak_h_err'],'FLAG','mm','zhc_peak_foot_h - (camera peak toe z in the stride - camera toe z at begin-ZVP). Sensor (dorsum) vs toe marker, both as rise above stance.','-','ZHC + camera');
end
for L = {'lead','trail'}
    S = add(S,[L{1} '_dotcam_place_err'],'FLAG','mm','ZHC stride length - camera toe stride (toe y at end-ZVP - toe y at begin-ZVP).','-','ZHC + camera');
end
% ---- 9. Camera reference ----
csrc = 'CrossingParams_TestN.mat (step 8)';
S = add(S,'lead_cam_min_clearance','REFERENCE/TARGET','mm','Min foot clearance: lowest toe/heel marker z while over the obstacle footprint (|y| <= w/2), incl. the y=0 heights, minus obstacle top (step 9 minClearance). Marker centres; no sole offset applied. Negative = below the top (contact/occlusion).','above top positive',csrc);
S = add(S,'trail_cam_min_clearance','REFERENCE/TARGET','mm','Same, trailing limb.','above top positive',csrc);
S = add(S,'lead_cam_takeoff_dist','REFERENCE/TARGET','mm','Step 8 lift_dist = near (approach) edge (-w/2) - this limb''s TOE y at its begin-ZVP (foot flat before the obstacle). Own-foot definition: for the LEAD limb this is the stance before the trail foot''s, a full step back (~65-110 cm), NOT the literature trail-toe distance.','positive = before the edge',csrc);
S = add(S,'trail_cam_takeoff_dist','REFERENCE/TARGET','mm','Same, trailing limb (its toe before the near edge; ~ the literature take-off distance).','positive = before the edge',csrc);
S = add(S,'lead_cam_landing_dist','REFERENCE/TARGET','mm','Step 8 land_dist = this limb''s HEEL y at its end-ZVP - far edge (+w/2). Lead = literature landing distance.','positive = past the edge',csrc);
S = add(S,'trail_cam_landing_dist','REFERENCE/TARGET','mm','Same, trailing limb (a full step past the obstacle).','positive = past the edge',csrc);
S = add(S,'lead_cam_peak_foot_h','REFERENCE/TARGET','mm','Peak camera toe-marker z over the stride (absolute height of the marker centre above the floor plane).','up positive','CameraSynced_TestN.mat');
S = add(S,'trail_cam_peak_foot_h','REFERENCE/TARGET','mm','Same, trailing limb.','up positive','CameraSynced_TestN.mat');
S = add(S,'cam_obstacle_h','REFERENCE/TARGET','mm','Measured obstacle top for THIS crossing: robust median of the obstacle-marker z over the lead stride - 20 mm marker radius (step 8 method, per crossing). Verifies height_cm.','-','CameraSynced_TestN.mat');
S = add(S,'cam_obstacle_x','REFERENCE/TARGET','mm','Measured obstacle-marker y over the lead stride (the frame is obstacle-centred, so ~0).','-','CameraSynced_TestN.mat');
% ---- 10. Quality & inclusion ----
S = add(S,'contact_flag','FLAG','0/1','1 if lead or trail min clearance <= 0 mm (possible contact, or marker occlusion).','-',B);
S = add(S,'data_quality_flag','FLAG','0/1','1 if the crossings file flags the pass, a selected stride''s toe did not span y=0, the step-7 role of a stride disagrees with the crossings file, or a lead/trail stride is longer than 2.5 s (not a walking stride, e.g. a pause).','-',B);
S = add(S,'missing_dot','FLAG','0/1','1 if any Dot segment angle is unavailable in either swing.','-',B);
S = add(S,'missing_camera','FLAG','0/1','1 if camera toe data are missing at either stride''s ZVPs.','-',B);
S = add(S,'missing_event','FLAG','0/1','1 if either limb has no ZVP stride, or no toe-off/heel-strike inside it.','-',B);
S = add(S,'cleaned_variables','FLAG','-','Semicolon list of columns cleaned in this row (Test 106 thigh MAD gate); originals in exclusions_log.csv.','-',B);
S = add(S,'include_biomech','FLAG','0/1','1 = no missing event, no missing Dot, no data-quality flag. Contact rows are kept (see contact_flag).','-',B);
S = add(S,'include_ml','FLAG','0/1','include_biomech AND not trajectory_invalid AND no ZHC drift flag.','-',B);
% ---- 11. v2 additions ----
for L = {'lead','trail'}
    S = add(S,[L{1} '_dotcam_toe_peak_err'],'FLAG','mm','zhc_peak_toe_h - camera toe rise (camera peak toe z in the stride - toe z at begin-ZVP), same camera term as dotcam_peak_h_err. Uses camera data.','-','ZHC + Dot tilt + camera');
end
for L = {'lead','trail'}
    S = add(S,[L{1} '_cam_takeoff_toeoff'],'REFERENCE/TARGET','mm',['Literature-style take-off: near edge (-w/2) - this limb''s camera TOE y at its OWN toe-off (step-4 IMU toe-off event). ' ...
        'For the lead limb this is the toe position when it leaves the floor behind the trail foot; compare cam_takeoff_dist (toe at its begin-ZVP).'],'positive = before the edge','CameraSynced + Seg.toeL/R');
end
S = add(S,'role_imu','META','L/R',['Leading side recovered from the Dot ALONE: the strides whose ZHC apex is > 2 x the participant''s median stride apex are crossing candidates; consecutive L/R candidates within 1.5 s form one crossing and the earlier one leads. ' ...
    'Matched to this row as the IMU crossing nearest the camera crossing time (within 1.5 s; the matching is evaluation only). Empty for level rows or if no IMU crossing matched.'],'-',B);
S = add(S,'role_agree','REFERENCE','0/1','1 if role_imu equals leading_limb (camera). Uses camera roles.','-',B);
S = add(S,'imu_cross_stride_match','REFERENCE','0/1','1 if the IMU-detected lead AND trail crossing strides are the same ZVP strides as the camera-selected ones.','-',B);
S = add(S,'include_ml_noflag','FLAG','0/1','include_biomech AND not trajectory_invalid (the ZHC drift flag is ignored). For running the models both ways.','-',B);
S = add(S,'block_id','META','-','Block number within the participant: run of consecutive rows (by trial_order) with the same obstacle_code (level passes form their own block). Never a feature.','-',B);
S = add(S,'block_pos','META','-','Position of the row inside its block (1..n). Never a feature (anticipation / learning).','-',B);
end

function c = obstacleOnlyCols()
% Columns that do not apply to level walks (no obstacle) - not counted as missing there.
c = {'cam_min_clearance','cam_takeoff_dist','cam_landing_dist','cam_obstacle_h','cam_obstacle_x', ...
     'cam_takeoff_toeoff','role_agree','imu_cross_stride_match'};
end

%% ========================================================================
%  DICTIONARY + REPORT
%% ========================================================================
function writeDictionary(f, S, CFG)
fid = fopen(f, 'w');  assert(fid > 0, 'cannot open %s', f);
c = onCleanup(@() fclose(fid));
fprintf(fid, '# Data dictionary — Crossing_Master_%s.csv\n\n', CFG.cohort);
fprintf(fid, '_Generated by `Analysis/ML/build_crossing_master.m` on %s._\n\n', char(datetime('now','Format','yyyy-MM-dd HH:mm')));
fprintf(fid, ['One row = one obstacle crossing (participant x obstacle x repeat) or one level walk (`is_level` = 1). ' ...
    'Both limbs are in the row, named by role (`lead_`, `trail_`). Empty cell = not computed (never imputed).\n\n']);
fprintf(fid, '## Roles\n\n- **ID** identifiers · **LABEL** encodes the obstacle (never a feature: leakage) · **META** design/participant/event info · ');
fprintf(fid, '**FEATURE** wearable (Dot) inputs · **FLAG** quality/inclusion · **REFERENCE / TARGET** camera values (never features).\n\n');
fprintf(fid, '## Definitions confirmed against the existing code\n\n');
fprintf(fid, ['- **Stride** = ZVP -> ZVP (mid-stance -> mid-stance) of one foot, from the Dot foot IMU (step 4; saved, hand-edited ZVPs). ' ...
    '**Swing** = the step-4 toe-off (inverted foot-roll minimum) -> heel-strike (foot-roll maximum) inside that stride; all `%% swing` values use that window (0 = toe-off, 100 = heel-strike).\n']);
fprintf(fid, ['- **Segment sign** (Dot thigh/shank/foot euler X): sign-normalized per participant x side with step 9''s templates (`signTemplates.mat`, ' ...
    'level-walk shape correlation + polarity anchor: thigh forward-tilt dominant positive, shank heel-up dominant negative, foot toe-down dominant negative). ' ...
    'So max = thigh forward / shank forward / foot toe-up and min = thigh backward / shank backward (heel-up) / foot toe-down. The thigh and shank anchors are a ' ...
    'physiological convention (the camera has no thigh/shank markers); the foot sign is checked against the camera foot pitch in build_report.md.\n']);
fprintf(fid, '- **Offset correction**: `_corr` = value - the angle at the same stride''s begin-ZVP (median of the first %d of 200 normalized samples; step 9''s peak-excursion reference). Raw `_max`/`_min` are not offset-corrected.\n', CFG.refW);
fprintf(fid, ['- **Camera frame** (WorldViz PPT, refined CV trajectory): y = walkway, obstacle centre at y = 0, z = height; marker centres (no sole offset; obstacle top = marker - 20 mm). ' ...
    'Clearance = foot z over the obstacle - obstacle top. Take-off = near edge - own TOE y at begin-ZVP; landing = own HEEL y at end-ZVP - far edge (per limb, as step 8).\n']);
fprintf(fid, ['- **ZHC frame**: Dot global frame (gravity z-up, heading from the Dot fusion), integrated per stride from that stride''s begin-ZVP (origin), level-ground bias solve ' ...
    '(end height forced to 0). Only the foot **sensor** position is integrated; the toe height (`*_zhc_peak_toe_h`, v2) is derived from it by a rigid-body transform with the Dot foot tilt.\n']);
fprintf(fid, '- **Acceleration windows**: first / last %d%% of the swing.\n', round(100*CFG.accWinFrac));
fprintf(fid, ['- **Level walks**: per level pass, the stride in which each toe crosses camera y = 0 (the obstacle location) moving +y, before the first labelled obstacle pass and outside every labelled one (the crossings file lists the level passes as unlabelled rows); both feet must be seen at y = 0; ' ...
    'lead = the foot that crosses first; same swing window and features.\n']);
fprintf(fid, '- **Sync**: Dot clock = camera clock + `dot_cam_sync_offset_s` (step 5, 3x left-leg raise).\n\n');
fprintf(fid, '## Study-design notes (v2)\n\n');
fprintf(fid, ['- **Roles and crossing strides are camera-derived.** `leading_limb`, every lead_/trail_ assignment and the stride chosen for each limb come from the camera crossings file ' ...
    '(which foot passes y = 0 first, and the ZVP stride containing that instant). `role_imu` recovers the leading side from the Dot alone and `role_agree` / `imu_cross_stride_match` ' ...
    'show how often it matches (build_report.md, task 5). An unseen-participant model that uses lead_/trail_ features therefore assumes the role and stride are known.\n']);
fprintf(fid, ['- **`height_cm` is the obstacle height used by step 8, not the nominal design height.** For 103-110 it is measured from the obstacle markers (marker centre - 20 mm); ' ...
    'for 101-102 it is 10/20/30%% of the typed leg length. It can differ from 10/20/30%% of the leg length; the marker heights show a set-up change between Tests 104 and 105 (build_report.md, task 1).\n']);
fprintf(fid, ['- **Obstacles were run in blocks** of ~5 consecutive repeats (`order_randomized` should be "no"; `block_id`, `block_pos`), with a block order that differs between participants. ' ...
    'Anticipation and within-block learning are possible; `trial_order`, `block_id` and `block_pos` are META and must never be features.\n']);
fprintf(fid, ['- **`lead_cam_takeoff_dist` is the own-foot definition** (lead toe at the lead limb''s begin-ZVP, i.e. its stance before the trail foot''s, a full step back), not the literature value. ' ...
    '`lead_cam_takeoff_toeoff` / `trail_cam_takeoff_toeoff` give the toe distance before the near edge at the limb''s own toe-off; the literature "trail foot placement" ' ...
    'is `trail_cam_takeoff_dist`.\n\n']);
fprintf(fid, '## Columns (%d)\n\n| # | name | role | unit | definition | sign convention | source |\n|---|---|---|---|---|---|---|\n', size(S,1));
for k = 1:size(S,1)
    fprintf(fid, '| %d | `%s` | %s | %s | %s | %s | %s |\n', k, S{k,1}, S{k,2}, S{k,3}, S{k,4}, S{k,5}, S{k,6});
end
fprintf(fid, '\nProduced by `Analysis/ML/build_crossing_master.m` (functions `limbFeat`, `fillCrossing`, `levelPasses`, `applyCleaning`).\n');
end

function writeReport(f, T, Traw, SIDE, QC, SPEC, CFG, root, xlog)
fid = fopen(f, 'w');  assert(fid > 0, 'cannot open %s', f);
c = onCleanup(@() fclose(fid));
fprintf(fid, '# Build report — Crossing_Master_%s\n\n_Generated %s._\n\n', CFG.cohort, char(datetime('now','Format','yyyy-MM-dd HH:mm')));
P = unique(T.participant_id)';
% ---- 1. row counts ----
fprintf(fid, '## 1. Row counts (expected 30 crossings + 5 level walks per participant)\n\n');
fprintf(fid, '| participant | crossings | level | per-code counts | include_ml | notes |\n|---|---|---|---|---|---|\n');
codes = {'11','12','13','21','22','23'};
for p = P
    s = T.participant_id == p;  ob = s & T.is_level == 0;
    cc = cellfun(@(k) sum(strcmp(T.obstacle_code(ob), k)), codes);
    q = QC{cellfun(@(x) x.tn == p, QC)};
    dev = {};
    if nnz(ob) ~= 30, dev{end+1} = sprintf('%d crossings', nnz(ob)); end %#ok<AGROW>
    if any(cc ~= 5), dev{end+1} = ['codes ' strjoin(codes(cc ~= 5), '/') ' ~= 5']; end %#ok<AGROW>
    if sum(s & T.is_level == 1) ~= 5, dev{end+1} = sprintf('%d level', sum(s & T.is_level == 1)); end %#ok<AGROW>
    if q.nUnlab > 0, dev{end+1} = sprintf('%d unlabelled camera passes skipped', q.nUnlab); end %#ok<AGROW>
    dev = [dev, q.notes]; %#ok<AGROW>
    fprintf(fid, '| %d | %d | %d | %s | %d | %s |\n', p, nnz(ob), sum(s & T.is_level==1), ...
        strjoin(arrayfun(@(k) sprintf('%s:%d', codes{k}, cc(k)), 1:6, 'UniformOutput', false), ' '), ...
        sum(s & T.include_ml == 1), strjoin(dev, '; '));
end
for q = 1:numel(QC)
    if isempty(QC{q}.notes) || any(P == QC{q}.tn), continue; end
    fprintf(fid, '| %d | - | - | - | - | %s |\n', QC{q}.tn, strjoin(QC{q}.notes, '; '));
end
lvA = cellfun(@(x) x.lvFeatLogAgree, QC);
fprintf(fid, '\nLevel strides chosen at y = 0 that the Dot app FeatureLog also tagged Level_Walk: %s.\n\n', ...
    strjoin(arrayfun(@(k) sprintf('%d: %.0f%%', QC{k}.tn, 100*lvA(k)), 1:numel(QC), 'UniformOutput', false), ', '));
% ---- 2. ids & labels ----
fprintf(fid, '## 2. IDs and labels\n\n');
fprintf(fid, '- crossing_id unique: **%s** (%d rows, %d unique).\n', yesno(numel(unique(T.crossing_id)) == height(T)), height(T), numel(unique(T.crossing_id)));
ob = T.is_level == 0;  bad = 0;
for i = find(ob)'
    cd = T.obstacle_code{i};
    ok = strcmp(T.width_class{i}, ['W' cd(1)]) && strcmp(T.height_class{i}, ['H' cd(2)]) && ...
         T.width_cm(i) == CFG.width_cm(str2double(cd(1))) && T.height_pct_LL(i) == CFG.heightPct(str2double(cd(2)));
    bad = bad + ~ok;
end
fprintf(fid, '- label columns consistent with obstacle_code: **%s** (%d inconsistent).\n', yesno(bad == 0), bad);
fprintf(fid, '- Leading/trailing source: camera crossings file (Dot Logger files of Tests 101-110 contain no "Leading leg" lines). Rows whose step-7 stride role disagrees: %d (data_quality_flag).\n\n', sum(T.data_quality_flag == 1));
% ---- 3. missingness ----
fprintf(fid, '## 3. Missing values\n\n### Columns never computed\n\n');
allNan = {};
for k = 1:size(SPEC,1)
    x = T.(SPEC{k,1});
    if isnumeric(x) && all(isnan(x)), allNan{end+1} = SPEC{k,1}; fprintf(fid, '- `%s` — %s\n', SPEC{k,1}, SPEC{k,4}); end %#ok<AGROW>
end
fprintf(fid, '\n### Missing per column (FEATURE / REFERENCE / TARGET with any gap; obstacle-only columns counted on obstacle rows)\n\n| column | role | n missing | of |\n|---|---|---|---|\n');
obsOnly = obstacleOnlyCols();
for k = 1:size(SPEC,1)
    nm = SPEC{k,1};  x = T.(nm);
    if ~isnumeric(x) || any(strcmp(nm, allNan)) || ~any(contains(SPEC{k,2}, {'FEATURE','REFERENCE','TARGET'})), continue; end
    rr = true(height(T),1);  if any(endsWith(nm, obsOnly)), rr = T.is_level == 0; end
    nm_ = sum(isnan(x(rr)));
    if nm_ > 0, fprintf(fid, '| `%s` | %s | %d | %d |\n', nm, SPEC{k,2}, nm_, nnz(rr)); end
end
fprintf(fid, '\n### Missing FEATURE cells per participant (excluding never-computed columns)\n\n| participant | rows | missing cells | %% of feature cells |\n|---|---|---|---|\n');
fcols = SPEC(strcmp(SPEC(:,2),'FEATURE'), 1)';  fcols = setdiff(fcols, allNan, 'stable');
for p = P
    s = T.participant_id == p;  M = T{s, fcols};  nmiss = sum(isnan(M(:)));
    fprintf(fid, '| %d | %d | %d | %.1f |\n', p, nnz(s), nmiss, 100*nmiss/numel(M));
end
% ---- 4. ranges ----
fprintf(fid, '\n## 4. Plausibility / impossible values\n\n');
R = {'^(lead|trail)_(thigh|shank|foot)_(max|min|max_corr|min_corr)$', -180, 180, 'segment angle'; '_av_(max|min|toeoff)$', -1500, 1500, 'angular velocity'; '^(lead|trail)_(thigh|shank|foot)_rom$', 0, 180, 'segment ROM'; '_t_max$|_t_min$|_h_t$', 0, 100, '% swing'; ...
     'swing_time$', 0.2, 1.5, 'swing time'; 'stance_time$', 0.2, 2.5, 'stance time'; 'speed', 0.2, 3, 'speed'; ...
     '^cadence$', 30, 200, 'cadence'; 'zhc_peak_foot_h$', 10, 800, 'ZHC peak height'; 'cam_min_clearance$', 0, 1000, 'clearance'; ...
     'cam_takeoff_dist$|cam_landing_dist$', -100, 2000, 'take-off/landing'; 'foot_acc', 0, 200, 'foot acc'; 'stance_conf', 0, 1, 'stance conf'};
fprintf(fid, '| check | column | range | n outside | examples |\n|---|---|---|---|---|\n');
for k = 1:size(R,1)
    cols = SPEC(~cellfun(@isempty, regexp(SPEC(:,1), R{k,1}, 'once')), 1)';
    for j = 1:numel(cols)
        x = T.(cols{j});  if ~isnumeric(x), continue; end
        o = find(isfinite(x) & (x < R{k,2} | x > R{k,3}));
        if isempty(o), continue; end
        ex = strjoin(arrayfun(@(i) sprintf('%s=%.1f', T.crossing_id{i}, x(i)), o(1:min(3,end))', 'UniformOutput', false), ', ');
        fprintf(fid, '| %s | `%s` | %g..%g | %d | %s |\n', R{k,4}, cols{j}, R{k,2}, R{k,3}, numel(o), ex);
    end
end
fprintf(fid, '\nRows with contact_flag = 1 (min clearance <= 0): %d.\n\n', sum(T.contact_flag == 1));
% ---- 5. SPSS cross-check ----
writeSpssCheck(fid, T, SIDE, root);
% ---- 6. ZHC quality ----
fprintf(fid, '\n## 6. ZHC quality\n\n| participant | lead h@landing mean±SD (mm) | trail h@landing | drift flags | lead Dot-cam peak-h err mean±SD (mm) | trail | lead place err mean±SD (mm) | trail |\n|---|---|---|---|---|---|---|---|\n');
for p = [P NaN]
    if isnan(p), s = true(height(T),1); lab = '**all**'; else, s = T.participant_id == p; lab = num2str(p); end
    fprintf(fid, '| %s | %s | %s | %d | %s | %s | %s | %s |\n', lab, ms(T.lead_zhc_h_landing(s)), ms(T.trail_zhc_h_landing(s)), ...
        sum(T.lead_zhc_drift_flag(s) == 1) + sum(T.trail_zhc_drift_flag(s) == 1), ...
        ms(T.lead_dotcam_peak_h_err(s)), ms(T.trail_dotcam_peak_h_err(s)), ms(T.lead_dotcam_place_err(s)), ms(T.trail_dotcam_place_err(s)));
end
sdT = cell2table(SIDE(:,[1 3 10]), 'VariableNames', {'tn','role','d'});
fprintf(fid, ['\nUncorrected ZHC landing drift (end-ZVP height before the level-ground correction), |mm|: median %.1f, 95th pct %.1f; ' ...
    'drift-flag threshold = %.1f mm (median + %g x 1.4826 x MAD). Per participant median |drift| (lead / trail): %s.\n'], ...
    median(abs(sdT.d),'omitnan'), prctile(abs(sdT.d),95), CFG.driftThr_mm, CFG.driftMadK, ...
    strjoin(arrayfun(@(p) sprintf('%d %.0f/%.0f', p, median(abs(sdT.d(sdT.tn==p & strcmp(sdT.role,'lead'))),'omitnan'), ...
    median(abs(sdT.d(sdT.tn==p & strcmp(sdT.role,'trail'))),'omitnan')), unique(sdT.tn)', 'UniformOutput', false), ', '));
fprintf(fid, '\nFoot sign check (median per participant of corr(Dot foot tilt, camera foot pitch) over the swing; + = Dot max is toe-up):\n\n');
fprintf(fid, '| participant | lead r | trail r | sign flips applied (L/R thigh, shank, foot) |\n|---|---|---|---|\n');
for q = 1:numel(QC)
    if ~isfield(QC{q},'flip'), continue; end
    fl = QC{q}.flip;
    fprintf(fid, '| %d | %.2f | %.2f | L %d %d %d / R %d %d %d |\n', QC{q}.tn, QC{q}.footSignR(1), QC{q}.footSignR(2), ...
        fl.L_thigh, fl.L_shank, fl.L_foot, fl.R_thigh, fl.R_shank, fl.R_foot);
end
% ---- 7. n per variable + Test 106 cleaning ----
fprintf(fid, '\n## 7. n per variable and Test 106 cleaning\n\n| column | role | n (all rows) | n (include_ml) |\n|---|---|---|---|\n');
for k = 1:size(SPEC,1)
    nm = SPEC{k,1};  x = T.(nm);
    if ~isnumeric(x) || ~any(contains(SPEC{k,2}, {'FEATURE','REFERENCE','TARGET'})) || any(strcmp(nm, allNan)), continue; end
    fprintf(fid, '| `%s` | %s | %d | %d |\n', nm, SPEC{k,2}, sum(isfinite(x)), sum(isfinite(x) & T.include_ml == 1));
end
cl = xlog(strcmp(xlog(:,6), 'cleaned'), :);
fprintf(fid, '\nTest 106 MAD gate: %d values set to NaN.\n\n| column | code | n removed | 106 mean raw | 106 mean cleaned |\n|---|---|---|---|---|\n', size(cl,1));
if ~isempty(cl)
    s106 = T.participant_id == 106 & T.is_level == 0;
    [u, ~, j] = unique(cellfun(@(id, v) [v '|' regexprep(id, '^\d+_(\d+)_r\d+$', '$1')], cl(:,2), cl(:,3), 'UniformOutput', false));
    for k = 1:numel(u)
        pr = strsplit(u{k}, '|');  rr = s106 & strcmp(T.obstacle_code, pr{2});
        fprintf(fid, '| `%s` | %s | %d | %.1f | %.1f |\n', pr{1}, pr{2}, sum(j == k), mean(Traw.(pr{1})(rr), 'omitnan'), mean(T.(pr{1})(rr), 'omitnan'));
    end
end
end

function writeSpssCheck(fid, T, SIDE, root)
fprintf(fid, '## 5. Cross-check against the SPSS sheet (per participant x condition means)\n\n');
f = fullfile(root,'Results','Group Analysis','GroupCrossing_YoungAdults_SPSS.xlsx');
if ~isfile(f), fprintf(fid, 'SPSS sheet not found.\n'); return; end
Sp = readtable(f, 'VariableNamingRule','preserve');  vn = Sp.Properties.VariableNames;
sd = cell2table(SIDE, 'VariableNames', {'tn','id','role','code','stride_mm','stride_s','rom_thigh','rom_shank','rom_foot','rawDrift','footR'});
% {SPSS name, master/side source, role, scale(master->SPSS units), note}
CK = {'clearance_min',     'cam_min_clearance', 0.1, 'cm';
      'clearance_takeoff', 'cam_takeoff_dist',  0.1, 'cm';
      'clearance_landing', 'cam_landing_dist',  0.1, 'cm';
      'spatiotemporal_stride', 'side:stride_mm', 0.1, 'cm (ZHC ZVP stride)';
      'spatiotemporal_cadence','side:cadence',   1,   'steps/min';
      'spatiotemporal_speed',  'side:speed',     1,   'm/s';
      'segment_thigh_rom', 'side:rom_thigh', 1, 'deg, ZVP->ZVP stride ROM';
      'segment_shank_rom', 'side:rom_shank', 1, 'deg';
      'segment_foot_rom',  'side:rom_foot',  1, 'deg';
      'segment_thigh_rom', 'thigh_rom', 1, 'deg, master = SWING ROM (expected smaller)';
      'segment_foot_rom',  'foot_rom',  1, 'deg, master = SWING ROM (expected smaller)'};
roles = {'Leading','lead'; 'Trailing','trail'};
codes = {'11','12','13','21','22','23'};
fprintf(fid, '| SPSS variable | master source | n pairs | mean diff (master - SPSS) | max abs diff | worst |\n|---|---|---|---|---|---|\n');
for k = 1:size(CK,1)
    d = [];  lab = {};
    for p = unique(T.participant_id)'
        ip = find(Sp.Test == p, 1);  if isempty(ip), continue; end
        for ci = 1:6
            cd = codes{ci};  cond = sprintf('W%s_H%s', cd(1), cd(2));
            for ri = 1:2
                col = sprintf('%s_%s_%s', CK{k,1}, cond, roles{ri,1});
                if ~any(strcmp(vn, col)), continue; end
                ref = Sp.(col)(ip);
                if startsWith(CK{k,2}, 'side:')
                    q = strrep(CK{k,2}, 'side:', '');
                    s = sd.tn == p & strcmp(sd.code, cd) & strcmp(sd.role, roles{ri,2});
                    switch q
                        case 'cadence', v = 120 ./ sd.stride_s(s);
                        case 'speed',   v = (sd.stride_mm(s)/1000) ./ sd.stride_s(s);
                        otherwise,      v = sd.(q)(s);
                    end
                else
                    s = T.participant_id == p & strcmp(T.obstacle_code, cd);
                    v = T.([roles{ri,2} '_' CK{k,2}])(s);
                end
                m = mean(v, 'omitnan') * CK{k,3};
                if isfinite(m) && isfinite(ref), d(end+1) = m - ref; lab{end+1} = sprintf('%d %s %s', p, cond, roles{ri,1}); end %#ok<AGROW>
            end
        end
    end
    if isempty(d), fprintf(fid, '| `%s` | %s | 0 | - | - | - |\n', CK{k,1}, CK{k,2}); continue; end
    [mx, im] = max(abs(d));
    fprintf(fid, '| `%s` (%s) | %s | %d | %.3f | %.3f | %s |\n', CK{k,1}, CK{k,4}, CK{k,2}, numel(d), mean(d), mx, lab{im});
end
fprintf(fid, ['\nNotes: SPSS values are per-participant condition means from step 9 (Test 106 thigh = MAD-gated median, so its ROM differs). ' ...
    'SPSS clearance/take-off/landing are cm; the master stores mm. The master''s segment ROM is the SWING ROM; the ZVP-cycle ROM rows above reproduce the SPSS definition.\n']);
end

function s = ms(x)
x = x(isfinite(x));
if isempty(x), s = '-'; else, s = sprintf('%.1f ± %.1f', mean(x), std(x)); end
end

function s = yesno(tf)
if tf, s = 'yes'; else, s = 'NO'; end
end

%% ========================================================================
%  v2 ADDITIONS (review follow-up): IMU-only role, toe height, blocks, checks
%% ========================================================================
function v = stepCheck(X, ll, tl, cL, cT)
% Feasibility check of a Dot step length (task 10): lead landing ZVP - trail stance ZVP
% in the continuous ZHC (pZvp, Dot global frame) vs the camera toe y difference.
v = [NaN NaN];
if ll == ' ' || tl == ' ' || isnan(cL) || isnan(cT), return; end
pl = X.(ll).pZvp;  pt = X.(tl).pZvp;  zl = X.(ll).zvp;  zt = X.(tl).zvp;
if isempty(pl) || isempty(pt) || cL + 1 > size(pl,1) || cT > size(pt,1), return; end
u = pl(cL+1,1:2) - pl(cL,1:2);  if norm(u) == 0, return; end
v(1) = (pl(cL+1,1:2) - pt(cT,1:2)) * (u / norm(u))' * 1000;
v(2) = X.(ll).toeM(zl(cL+1),2) - X.(tl).toeM(zt(cT),2);
end

function [rows, q] = imuRoles(rows, X, t, fs, CFG)
% IMU-only crossing detection (task 5). Candidates = strides whose ZHC apex (max height
% above the begin-ZVP) > CFG.imuApexK x the participant's median stride apex; consecutive
% opposite-foot candidates within imuPairTol_s = one crossing, the earlier foot leads.
% Each camera row is then matched to the IMU crossing nearest its camera lead time.
E = zeros(0,4);                                    % [apex time, side (1 L / 2 R), cycle, apex mm]
for sd = 'LR'
    Z = X.(sd).zhc;  z = X.(sd).zvp;  if isempty(Z), continue; end
    n = min(numel(z) - 1, size(Z,3));  pk = nan(n,1);  ta = nan(n,1);
    for c = 1:n
        L = z(c+1) - z(c) + 1;
        if L > size(Z,1) || (L-1)/fs > CFG.maxStride_s, continue; end
        h = Z(1:L,3,c);  if ~all(isfinite(h)), continue; end
        [m, im] = max(h - h(1));  pk(c) = m * 1000;  ta(c) = t(z(c) + im - 1);
    end
    E = [E; ta, repmat(1 + (sd == 'R'), n, 1), (1:n)', pk]; %#ok<AGROW>
end
E = E(isfinite(E(:,4)), :);
q = struct('nEvents',0,'nPairs',0,'nUnmatched',0,'thr_mm',NaN);
if isempty(E), return; end
q.thr_mm = CFG.imuApexK * median(E(:,4));
E = sortrows(E(E(:,4) > q.thr_mm, :), 1);  q.nEvents = size(E,1);
Pp = zeros(0,4);  k = 1;                           % [lead apex time, lead side, lead cycle, trail cycle]
while k < size(E,1)
    if E(k+1,2) ~= E(k,2) && E(k+1,1) - E(k,1) <= CFG.imuPairTol_s
        Pp(end+1,:) = [E(k,1) E(k,2) E(k,3) E(k+1,3)]; %#ok<AGROW>
        k = k + 2;
    else
        k = k + 1;
    end
end
q.nPairs = size(Pp,1);  used = false(q.nPairs,1);  sides = 'LR';
for i = 1:numel(rows)
    if rows(i).is_level == 1 || isempty(Pp), continue; end
    [d, j] = min(abs(Pp(:,1) - rows(i).lead_crossing_t_cam));
    if ~(d <= CFG.imuMatchTol_s), continue; end
    used(j) = true;
    rows(i).role_imu = sides(Pp(j,2));
    if ~isempty(rows(i).leading_limb)
        rows(i).role_agree = double(rows(i).role_imu == rows(i).leading_limb);
        rows(i).imu_cross_stride_match = double(rows(i).role_agree == 1 && ...
            Pp(j,3) == rows(i).lead_cyc && Pp(j,4) == rows(i).trail_cyc);
    end
end
q.nUnmatched = sum(~used);
end

function n = runCount(c, lab)
% Number of runs of consecutive cycles carrying label lab.
if ~iscell(c), n = 0; return; end
m = strcmpi(c(:), lab);  n = sum(diff([false; m]) == 1);
end

function [rows, TOE] = toeHeights(rows)
% Toe height from the foot sensor by a rigid-body transform (task 3). Model per swing
% sample: camToeRise - sensorRise = rx*sin(theta) + rz*(cos(theta)-1). The vector [rx rz]
% is fitted per participant (reported) and leave-one-participant-out (used for the column).
pid = [rows.participant_id];  P = unique(pid);  np = numel(P);
S = cell(np,1);
for i = 1:numel(rows)
    if rows(i).include_biomech ~= 1, continue; end
    k = find(P == pid(i));
    for pre = {'lead_','trail_'}
        A = rows(i).([pre{1} 'toefit']);  if ~isempty(A), S{k} = [S{k}; A]; end
    end
end
TOE = table(P(:), nan(np,1), nan(np,1), nan(np,1), nan(np,1), zeros(np,1), nan(np,1), ...
    'VariableNames', {'tn','rx_own','rz_own','rx_lopo','rz_lopo','n_samples','rmse_own'});
for k = 1:np
    [TOE.rx_own(k), TOE.rz_own(k), TOE.n_samples(k), TOE.rmse_own(k)] = fitToe(S{k});
    [TOE.rx_lopo(k), TOE.rz_lopo(k)] = fitToe(vertcat(S{[1:k-1, k+1:np]}));
end
for i = 1:numel(rows)
    k = find(P == pid(i));  r = [TOE.rx_lopo(k) TOE.rz_lopo(k)];
    if any(~isfinite(r)), continue; end
    for pre = {'lead_','trail_'}
        A = rows(i).([pre{1} 'toefit']);  if isempty(A), continue; end
        h = A(:,1) + r(1) * A(:,2) + r(2) * A(:,3);
        if ~any(isfinite(h)), continue; end
        pk = max(h);
        rows(i).([pre{1} 'zhc_peak_toe_h']) = pk;
        camRise = rows(i).([pre{1} 'zhc_peak_foot_h']) - rows(i).([pre{1} 'dotcam_peak_h_err']);
        rows(i).([pre{1} 'dotcam_toe_peak_err']) = pk - camRise;
    end
end
end

function [rx, rz, n, rmse] = fitToe(A)
% Least squares for [rx rz] with one 3-robust-SD residual trim, mm.
rx = NaN;  rz = NaN;  n = 0;  rmse = NaN;
if isempty(A), return; end
A = A(all(isfinite(A), 2), :);  n = size(A,1);
if n < 50, return; end
M = A(:,2:3);  y = A(:,4) - A(:,1);
b = M \ y;  e = y - M*b;  s = 1.4826 * median(abs(e - median(e)));
keep = abs(e - median(e)) <= 3*s;
b = M(keep,:) \ y(keep);  rx = b(1);  rz = b(2);
rmse = sqrt(mean((y(keep) - M(keep,:)*b).^2));
end

function rows = blockIds(rows)
% block_id / block_pos (task 9): runs of the same obstacle_code in trial_order.
pid = [rows.participant_id];
for p = unique(pid)
    ii = find(pid == p);  [~, o] = sort([rows(ii).trial_order]);  ii = ii(o);
    b = 0;  prev = '';  pos = 0;
    for i = ii
        if ~strcmp(rows(i).obstacle_code, prev), b = b + 1; pos = 0; prev = rows(i).obstacle_code; end
        pos = pos + 1;  rows(i).block_id = b;  rows(i).block_pos = pos;
    end
end
end

function writeReview(f, T, D, QC, TOE, xall, meta, CFG)
% Sections answering the v1 review (tasks 1-13), appended to build_report.md.
fid = fopen(f, 'a');  assert(fid > 0, 'cannot open %s', f);
c = onCleanup(@() fclose(fid));
P = unique(T.participant_id)';  ob = T.is_level == 0;  inc = T.include_ml == 1;
fprintf(fid, '\n---\n\n# v2 review follow-up (tasks 1-13)\n\n');
fprintf(fid, 'All tables: n = rows used; "all rows" = every row of the dataset (%d rows, %d obstacle, %d level), "include_ml" = %d rows.\n\n', ...
    height(T), nnz(ob), nnz(~ob), nnz(inc));

% ---------- 1. obstacle height audit ----------
fprintf(fid, ['## Task 1. Obstacle height audit\n\nPer participant x height class (obstacle rows, all rows). nominal = 10/20/30%% of the leg length (only where a leg length is known); ' ...
    'used = `height_cm` (step 8); marker = median per-crossing `cam_obstacle_h` (obstacle-marker centre - 20 mm); raw marker centre = marker + 2.0 cm. All cm.\n\n']);
fprintf(fid, '| participant | class | n | nominal | used (height_cm) | marker-based | raw marker centre | used - marker | nominal - used |\n|---|---|---|---|---|---|---|---|---|\n');
G = nan(numel(P), 3);  U = nan(numel(P), 3);  src = strings(numel(P),1);
for a = 1:numel(P)
    p = P(a);  ll = meta.leg_length_cm(meta.participant_id == p);  if isempty(ll), ll = NaN; end
    for H = 1:3
        s = ob & T.participant_id == p & strcmp(T.height_class, sprintf('H%d',H));
        U(a,H) = median(T.height_cm(s), 'omitnan');  G(a,H) = median(T.cam_obstacle_h(s), 'omitnan') / 10;
        nom = ll * CFG.heightPct(H) / 100;
        fprintf(fid, '| %d | H%d | %d | %s | %.1f | %.1f | %.1f | %+.1f | %s |\n', p, H, nnz(s), num1(nom), U(a,H), G(a,H), ...
            G(a,H) + CFG.markerR_mm/10, U(a,H) - G(a,H), sgn1(nom - U(a,H)));
    end
    if p <= 102, src(a) = "typed leg length"; else, src(a) = "auto markers"; end
end
fprintf(fid, ['\nLevel spacing from the marker-based heights (cm). With the bar at k x 10%% of the leg length, H2-H1 = H3-H2 = 10%% LL and H1 = one spacing. ' ...
    '"implied LL" = mean spacing / 0.10 is an INFERENCE, not written to `leg_length_cm`. "offset" = H1 - mean spacing (0 for a proportional set-up).\n\n']);
fprintf(fid, '| participant | step-8 source | H2-H1 | H3-H2 | implied LL | measured LL | offset (marker - 20 mm) | offset (raw marker centre) | raw marker - nominal (H1/H2/H3) | H3/H1 (used) |\n|---|---|---|---|---|---|---|---|---|---|\n');
off = nan(numel(P),1);
for a = 1:numel(P)
    d = diff(G(a,:));  sp = mean(d);  off(a) = G(a,1) - sp;
    ll = meta.leg_length_cm(meta.participant_id == P(a));  if isempty(ll), ll = NaN; end
    rn = G(a,:) + CFG.markerR_mm/10 - ll * CFG.heightPct / 100;
    fprintf(fid, '| %d | %s | %.1f | %.1f | %.0f | %s | %+.1f | %+.1f | %s / %s / %s | %.2f |\n', P(a), src(a), d(1), d(2), sp/0.10, num1(ll), ...
        off(a), off(a) + CFG.markerR_mm/10, sgn1(rn(1)), sgn1(rn(2)), sgn1(rn(3)), U(a,3)/U(a,1));
end
e = P <= 104;  l = P >= 105;  t2 = P <= 102;  k110 = find(P == 110, 1);
dTyped = G(t2,:) - U(t2,:);
fprintf(fid, ['\n**Finding.** The spacing between levels is close to 10%% of a plausible leg length for everyone, but the H1 offset jumps between Tests 104 and 105: ' ...
    'median offset %+.1f cm for 101-104 vs %+.1f cm for 105-110 with the 20 mm radius subtracted (%+.1f vs %+.1f cm for the raw marker centre). ' ...
    'The camera floor did not move (stance toe-marker z 54.5 mm in 104 vs 56.9 mm in 105, separate check), and the two obstacle markers stay at the bar ends (x = -370 / +370 mm) in every test, ' ...
    'so it is not a camera-calibration or marker-identity change. **Most likely cause:** the bar was set proportionally (k x 10%% LL) in every session, but the marker mount changed between 104 and 105. ' ...
    'In 101-104 the marker centre sits ~3.5-4 cm above the bar top (101-102: raw marker centre %.1f to %.1f cm above the typed leg-length heights), so subtracting 2 cm over-estimates 103-104 by ~1.5-3 cm; ' ...
    'in 105-110 the raw marker centre is AT a proportional height (offset ~0), so subtracting 2 cm UNDER-estimates 105-110 by ~2 cm, which is why their H1 looks low and H3/H1 is 3.5-4.5. ' ...
    'The measured leg lengths (lab sheet, hip to ankle) confirm this: raw marker centre - 10/20/30%% of the measured leg length is +3.4 to +4.7 cm in 101-104 and within +/-0.6 cm in 105-109, ' ...
    'so the bars were set proportionally and only the marker-to-top offset changed (~3.7 cm before 105, ~0 cm from 105). Test 110 is the exception: its spacing implies a 93 cm leg vs 83 cm measured ' ...
    '(H1/H2 ~0.8 cm below and H3 ~1.2 cm above nominal). Consequence: `height_cm` (marker - 2 cm) is ~1.5-2.5 cm too high for 103-104 and ~2 cm too low for 105-109, and the clearances shift by the same amount ' ...
    '(the "proportional" column in task 6 shows the effect). '], ...
    median(off(e)), median(off(l)), median(off(e)) + CFG.markerR_mm/10, median(off(l)) + CFG.markerR_mm/10, ...
    min(dTyped(:)) + CFG.markerR_mm/10, max(dTyped(:)) + CFG.markerR_mm/10);
if ~isempty(k110)
    fprintf(fid, 'Test 110 has unequal spacing (%.1f / %.1f cm). ', G(k110,2) - G(k110,1), G(k110,3) - G(k110,2));
end
fprintf(fid, '`height_cm` was NOT changed. Please confirm the bar heights (tape measure / lab notes) for at least one session before and after 105.\n\n');

% ---------- 2. metadata ----------
fprintf(fid, ['## Task 2. Participant metadata\n\nFilled in `Analysis/ML/participants_meta.csv` from the lab measurement sheet "Data Recording Measurements" (Google Sheet): age, body height, ' ...
    'mass (lb x 0.45359237 -> kg), dominant leg, and `leg_length_cm` = "Hip to ankle" (it equals the leg lengths typed into step 8 for 101 = 90 cm and 102 = 99 cm). ' ...
    'Segment and foot lengths are kept in the meta file for reference (not dataset columns). `sex` also comes from the sheet (6 F, 4 M; the PKMAS headers had listed only 101 as female).\n\n']);
fprintf(fid, 'Cells still empty:\n\n| participant | empty cells |\n|---|---|\n');
vv = {'age_y','sex','dominant_leg','body_height_cm','leg_length_cm','mass_kg','order_randomized'};
for p = P
    M = meta(meta.participant_id == p, :);  miss = {};
    for v = vv
        x = M.(v{1});
        if isempty(x) || (isnumeric(x) && isnan(x(1))) || (isstring(x) && strlength(x(1)) == 0), miss{end+1} = v{1}; end %#ok<AGROW>
    end
    fprintf(fid, '| %d | %s |\n', p, strjoin(miss, ', '));
end
fprintf(fid, '\n`order_randomized` is left for you: obstacles were run in blocks (task 9), with a block order that differs between participants.\n\n');

% ---------- 3. toe height ----------
fprintf(fid, ['## Task 3. Toe height from the ZHC (rigid-body sensor -> toe marker)\n\nModel per swing sample: toe rise = sensor rise + rx sin(theta) + rz (cos(theta) - 1), ' ...
    'theta = Dot foot tilt minus its begin-ZVP value (toe-up +). The foot length and sensor position are not stored, so [rx rz] (sensor -> toe marker, foot frame, mm) is fitted by least squares ' ...
    'to the camera toe-marker rise (swing samples of include_biomech rows, one 3-SD trim). The column uses the leave-one-participant-out (LOPO) vector, fitted on the other participants, ' ...
    'so it uses no camera data of the participant itself. With foot length and sensor position the vector could be measured instead.\n\n']);
fprintf(fid, '| participant | n samples | rx own | rz own | RMSE own | rx LOPO | rz LOPO | lead sensor err | lead toe err | trail sensor err | trail toe err |\n|---|---|---|---|---|---|---|---|---|---|---|\n');
for a = 1:height(TOE)
    s = T.participant_id == TOE.tn(a);
    fprintf(fid, '| %d | %d | %.0f | %.0f | %.0f | %.0f | %.0f | %s | %s | %s | %s |\n', TOE.tn(a), TOE.n_samples(a), TOE.rx_own(a), TOE.rz_own(a), TOE.rmse_own(a), ...
        TOE.rx_lopo(a), TOE.rz_lopo(a), ms(T.lead_dotcam_peak_h_err(s)), ms(T.lead_dotcam_toe_peak_err(s)), ms(T.trail_dotcam_peak_h_err(s)), ms(T.trail_dotcam_toe_peak_err(s)));
end
fprintf(fid, '| **all** | | | | | | | %s | %s | %s | %s |\n\nErrors = Dot - camera peak rise, mean ± SD (mm), all rows with both values.\n\n', ...
    ms(T.lead_dotcam_peak_h_err), ms(T.lead_dotcam_toe_peak_err), ms(T.trail_dotcam_peak_h_err), ms(T.trail_dotcam_toe_peak_err));
fprintf(fid, ['**Assessment.** The vector is poorly identified: the per-participant fits scatter widely (rx and rz of either sign) and the pooled LOPO vector is small ' ...
    '(rx ~15-25 mm, rz ~30-45 mm), so the toe transform mainly removes the trailing-limb bias (mean error %s -> %s mm) and leaves the SD almost unchanged. ' ...
    'The large trailing errors are not a lever-arm effect: the trailing foot crosses heel-up (camera heel peak up to ~200 mm above the toe peak), so the toe marker is the lowest point ' ...
    'of the foot and the ZHC sensor over-reads it (task 4). Treat `*_zhc_peak_toe_h` as provisional until the foot length and sensor position are measured.\n\n'], ...
    num1(mean(T.trail_dotcam_peak_h_err, 'omitnan')), num1(mean(T.trail_dotcam_toe_peak_err, 'omitnan')));

% ---------- 4. ZHC vs camera agreement ----------
fprintf(fid, ['## Task 4. ZHC vs camera peak height, within participant\n\nr = Pearson correlation across the participant''s rows (obstacle + level, all rows with both values); ' ...
    'camera rise = peak toe z in the stride - toe z at begin-ZVP.\n\n']);
fprintf(fid, '| participant | limb | n | r sensor | r toe | sensor err mean ± SD | toe err mean ± SD |\n|---|---|---|---|---|---|---|\n');
bad = zeros(0,2);
for p = P
    for L = {'lead','trail'}
        s = T.participant_id == p;  pk = T.([L{1} '_zhc_peak_foot_h'])(s);  er = T.([L{1} '_dotcam_peak_h_err'])(s);
        cr = pk - er;  tt = T.([L{1} '_zhc_peak_toe_h'])(s);  r1 = rr(pk, cr);
        fprintf(fid, '| %d | %s | %d | %.2f | %.2f | %s | %s |\n', p, L{1}, sum(isfinite(cr)), r1, rr(tt, cr), ms(er), ms(T.([L{1} '_dotcam_toe_peak_err'])(s)));
        if r1 < 0.6, bad(end+1,:) = [p, strcmp(L{1},'trail')]; end %#ok<AGROW>
    end
end
fprintf(fid, ['\nLargest sensor-height errors in the participant x limb cells with r < 0.6 (up to 5 each). gap = |IMU apex time - camera y=0 time|; drift = uncorrected landing drift; ' ...
    'cause = first rule that applies: gap > %.1f s -> timing; |drift| > threshold -> drift; camera heel peak > toe peak + 100 mm -> heel-up foot; camera rise < 30 mm -> camera; toe error < half the sensor error -> lever arm; else ZVP placement.\n\n'], CFG.syncGap_s);
fprintf(fid, '| crossing_id | limb | ZHC peak | camera rise | err | toe err | gap s | drift mm | flags | likely cause |\n|---|---|---|---|---|---|---|---|---|---|\n');
for b = 1:size(bad,1)
    L = 'lead';  if bad(b,2), L = 'trail'; end
    s = find(D.participant_id == bad(b,1));
    er = D.([L '_dotcam_peak_h_err'])(s);  [~, o] = sort(abs(er), 'descend', 'MissingPlacement','last');
    for j = o(1:min(5, sum(isfinite(er))))'
        i = s(j);  pk = D.([L '_zhc_peak_foot_h'])(i);  e1 = D.([L '_dotcam_peak_h_err'])(i);
        gap = abs(D.([L '_crossing_t_imu'])(i) - D.([L '_crossing_t_cam'])(i));  dr = D.([L '_zhc_raw_drift'])(i);
        te = D.([L '_dotcam_toe_peak_err'])(i);
        fl = sprintf('dq=%d inv=%d', D.data_quality_flag(i), D.trajectory_invalid(i));
        if gap > CFG.syncGap_s
            why = 'IMU apex not at the camera crossing (wrong stride / ZVP placement / sync)';
        elseif abs(dr) > CFG.driftThr_mm
            why = 'integration drift (drift flag)';
        elseif D.([L '_cam_heel_peak'])(i) - D.([L '_cam_peak_foot_h'])(i) > 100
            why = sprintf('foot heel-up over the obstacle: camera heel peak %.0f mm above the toe peak, the toe marker is the lowest point and the sensor rides high (sensor-to-toe geometry)', ...
                D.([L '_cam_heel_peak'])(i) - D.([L '_cam_peak_foot_h'])(i));
        elseif pk - e1 < 30
            why = 'camera rise implausibly low (toe occlusion / marker)';
        elseif abs(te) < 0.5*abs(e1)
            why = 'sensor vs toe lever arm (reduced by the toe transform)';
        elseif D.trajectory_invalid(i) == 1
            why = 'invalid ZHC trajectory';
        else
            why = 'ZHC height error without a timing / drift flag (ZVP placement of the begin/end stance)';
        end
        fprintf(fid, '| %s | %s | %.0f | %.0f | %+.0f | %s | %.2f | %.0f | %s | %s |\n', D.crossing_id{i}, L, pk, pk - e1, e1, sgn0(te), gap, dr, fl, why);
    end
end
dl = T.lead_crossing_t_imu - T.lead_crossing_t_cam;  dt = T.trail_crossing_t_imu - T.trail_crossing_t_cam;
fprintf(fid, '\nTiming mismatch counts (|IMU apex - camera y=0| > %.1f s): lead %d of %d, trail %d of %d rows.\n\n', CFG.syncGap_s, ...
    sum(abs(dl) > CFG.syncGap_s), sum(isfinite(dl)), sum(abs(dt) > CFG.syncGap_s), sum(isfinite(dt)));

% ---------- 5. IMU-only role ----------
fprintf(fid, ['## Task 5. IMU-only role and crossing-stride detection\n\nRule (Dot only): a stride is a crossing candidate if its ZHC apex > %.1f x the participant''s median stride apex; ' ...
    'consecutive L/R candidates within %.1f s form a crossing and the earlier foot leads. Evaluation: each camera row is matched to the nearest IMU crossing ' ...
    '(lead apex within %.1f s of the camera lead time). Obstacle rows only (level rows have no obstacle).\n\n'], CFG.imuApexK, CFG.imuPairTol_s, CFG.imuMatchTol_s);
fprintf(fid, '| participant | obstacle rows | apex threshold mm | IMU crossings | matched rows | role agree | crossing strides match | IMU crossings without a camera row |\n|---|---|---|---|---|---|---|---|\n');
for a = 1:numel(QC)
    q = QC{a};  if ~isfield(q,'imu'), continue; end
    s = ob & T.participant_id == q.tn;  m = s & ~cellfun(@isempty, T.role_imu);
    fprintf(fid, '| %d | %d | %.0f | %d | %d | %s | %s | %d |\n', q.tn, nnz(s), q.imu.thr_mm, q.imu.nPairs, nnz(m), pct(T.role_agree(m)), pct(T.imu_cross_stride_match(m)), q.imu.nUnmatched);
end
m = ob & ~cellfun(@isempty, T.role_imu);
fprintf(fid, '| **all** | %d | | | %d | %s | %s | |\n\n', nnz(ob), nnz(m), pct(T.role_agree(m)), pct(T.imu_cross_stride_match(m)));
fprintf(fid, 'Role agreement over ALL obstacle rows (unmatched counted as disagreement): %s.\n\n', pct([T.role_agree(m); zeros(nnz(ob) - nnz(m),1)]));

% ---------- 6. contacts ----------
fprintf(fid, ['## Task 6. Contact rows (min clearance <= 0 mm)\n\nAlternative heights: marker = this crossing''s `cam_obstacle_h`; proportional = k x (mean marker spacing) per participant ' ...
    '(a proxy for the nominal %% of leg length, which is unknown for 103-110). Clearance under another height = clearance + used height - other height. mm.\n\n']);
fprintf(fid, '| crossing_id | participant | code | side | limb | min clearance | height used | cam_obstacle_h | clearance (marker h) | clearance (proportional h) |\n|---|---|---|---|---|---|---|---|---|---|\n');
cnt = zeros(1,3);  nl = 0;
for i = find(ob)'
    a = P == T.participant_id(i);  H = str2double(T.height_class{i}(2));  sp = mean(diff(G(a,:))) * 10;
    for L = {'lead','trail'}
        c0 = T.([L{1} '_cam_min_clearance'])(i);  if ~isfinite(c0), continue; end
        hu = T.height_cm(i) * 10;  c1 = c0 + hu - T.cam_obstacle_h(i);  c2 = c0 + hu - H * sp;
        cnt = cnt + [c0 <= 0, c1 <= 0, c2 <= 0];  nl = nl + 1;
        if c0 <= 0
            sd = T.leading_limb{i};  if strcmp(L{1},'trail'), sd = setdiff('LR', sd); end
            fprintf(fid, '| %s | %d | %s | %s | %s | %.1f | %.0f | %.0f | %.1f | %.1f |\n', T.crossing_id{i}, T.participant_id(i), T.obstacle_code{i}, sd, L{1}, c0, hu, T.cam_obstacle_h(i), c1, c2);
        end
    end
end
fprintf(fid, '\nLimb crossings with clearance <= 0 (of %d lead + trail values on obstacle rows): used height %d, per-crossing marker height %d, proportional height %d.\n\n', nl, cnt(1), cnt(2), cnt(3));

% ---------- 7. drift flag sensitivity ----------
fprintf(fid, ['## Task 7. Drift flag sensitivity\n\nDrift flag = |uncorrected landing drift| > %.1f mm (cohort median + 3 x MAD). Rows with either limb flagged; all rows.\n\n' ...
    '| participant | rows | lead flags | trail flags | rows flagged | include_ml | include_ml_noflag |\n|---|---|---|---|---|---|---|\n'], CFG.driftThr_mm);
for p = [P NaN]
    if isnan(p), s = true(height(T),1); lab = '**all**'; else, s = T.participant_id == p; lab = num2str(p); end
    fl = T.lead_zhc_drift_flag(s) == 1 | T.trail_zhc_drift_flag(s) == 1;
    fprintf(fid, '| %s | %d | %d | %d | %d (%.0f%%) | %d | %d |\n', lab, nnz(s), sum(T.lead_zhc_drift_flag(s) == 1), sum(T.trail_zhc_drift_flag(s) == 1), ...
        nnz(fl), 100*mean(fl), sum(T.include_ml(s) == 1), sum(T.include_ml_noflag(s) == 1));
end
fprintf(fid, '\n| height class | rows | rows flagged |\n|---|---|---|\n');
for hc = {'level','H1','H2','H3'}
    s = strcmp(T.height_class, hc{1});  fl = T.lead_zhc_drift_flag(s) == 1 | T.trail_zhc_drift_flag(s) == 1;
    fprintf(fid, '| %s | %d | %d (%.0f%%) |\n', hc{1}, nnz(s), nnz(fl), 100*mean(fl));
end

% ---------- 8. cleaning sensitivity ----------
fprintf(fid, ['\n## Task 8. Thigh 3xMAD gate on every participant (sensitivity)\n\nSame rule as Test 106 (per participant x code x role, >= 4 values, |x - median| > 3 x 1.4826 x MAD -> NaN) ' ...
    'on thigh_max/min/rom/max_corr/min_corr (10 columns x ~30 obstacle rows = ~300 cells per participant). Not applied to the dataset: the values it would remove are in `exclusions_log.csv` with action "sensitivity only (not applied)".\n\n| participant | values removed | rows touched |\n|---|---|---|\n']);
for p = P
    k = cellfun(@(x) isequal(x, p), xall(:,1));
    fprintf(fid, '| %d | %d | %d |\n', p, nnz(k), numel(unique(xall(k,2))));
end
n106 = sum(cellfun(@(x) isequal(x,106), xall(:,1)));
fprintf(fid, ['\nTotal %d (Test 106: %d, others: %d). With only ~5 repeats per cell the MAD is small, so a 3xMAD gate removes some values in every participant by construction: ' ...
    'outside 106 these are mostly ordinary between-repeat variation, not sensor faults. Use these log lines only as a sensitivity check.\n\n'], size(xall,1), n106, size(xall,1) - n106);

% ---------- 9. blocks ----------
fprintf(fid, '## Task 9. Block structure\n\n`block_id` / `block_pos` added (META, never features). Block order by trial_order (L = level passes):\n\n| participant | obstacle blocks | block order |\n|---|---|---|\n');
seqs = strings(numel(P),1);
for a = 1:numel(P)
    s = find(T.participant_id == P(a));  [~, o] = sort(T.trial_order(s));  s = s(o);
    [~, fi] = unique(T.block_id(s), 'stable');  cds = T.obstacle_code(s(fi));  cds(strcmp(cds,'level')) = {'L'};
    seqs(a) = strjoin(cds, ' ');
    fprintf(fid, '| %d | %d | %s |\n', P(a), sum(~strcmp(cds,'L')), seqs(a));
end
fprintf(fid, '\nSame block order across participants: **%s** (%d distinct orders). A participant with exactly 6 obstacle blocks ran each obstacle in one block of consecutive repeats.\n\n', ...
    yesno(numel(unique(seqs)) == 1), numel(unique(seqs)));

% ---------- 10. step length ----------
fprintf(fid, ['## Task 10. Step length across the obstacle from the Dot\n\nCheck: lead step = lead foot at its landing ZVP - trail foot at its stance ZVP, both from the continuous ZHC ' ...
    '(`Seg.zhc.pZvp`, Dot global frame), projected on the lead stride direction, vs the camera toe y difference at the same ZVPs. Obstacle rows.\n\n' ...
    '| participant | n | Dot median mm | camera median mm | r | error median mm |\n|---|---|---|---|---|---|\n']);
sc = D.stepchk;
for p = P
    s = D.participant_id == p & D.is_level == 0 & all(isfinite(sc), 2);
    fprintf(fid, '| %d | %d | %.0f | %.0f | %.2f | %.0f |\n', p, nnz(s), median(sc(s,1)), median(sc(s,2)), rr(sc(s,1), sc(s,2)), median(sc(s,1) - sc(s,2)));
end
fprintf(fid, ['\n**Not feasible.** The continuous ZHC of each foot accumulates metres of drift over a trial (heading drift between the two sensors, nothing ties one foot to the other), ' ...
    'so the two feet have no usable common origin; re-anchoring within a pass would need a moment with the feet at a known relative position, which the protocol does not give. ' ...
    '`lead_cross_step_len` / `trail_cross_step_len` stay empty.\n\n']);

% ---------- 11. level rows ----------
fprintf(fid, '## Task 11. Level rows\n\n| participant | level rows | toe y=0 crossings before the first obstacle (L / R) | Dot app FeatureLog Level_Walk bouts (L / R) |\n|---|---|---|---|\n');
for a = 1:numel(QC)
    q = QC{a};
    fprintf(fid, '| %d | %d | %d / %d | %d / %d |\n', q.tn, sum(T.participant_id == q.tn & ~ob), q.lvCand(1), q.lvCand(2), q.lvFeatBouts(1), q.lvFeatBouts(2));
end
fprintf(fid, ['\nTotal %d level rows. A level row needs BOTH feet seen crossing y = 0 in the same pass; where the camera has more single-foot crossings than rows, one foot was occluded at y = 0. ' ...
    'The Dot app FeatureLog tags Level_Walk strides without the camera; those could become extra level rows (lead = first foot, a stride in the middle of the bout), ' ...
    'but the "same location as the obstacle" definition would then not hold. **No rows were added.**\n\n'], nnz(~ob));

% ---------- 12. dictionary ----------
fprintf(fid, ['## Task 12. Dictionary\n\nAdded to `data_dictionary.md` (section "Study-design notes"): camera-derived roles and crossing strides (with the role_imu result), `height_cm` = measured, not nominal, ' ...
    'blocked order, own-foot take-off. Literature-style take-off added as `lead_cam_takeoff_toeoff` / `trail_cam_takeoff_toeoff` (toe y at the limb''s own toe-off). Obstacle rows:\n\n']);
fprintf(fid, '| column | n | median mm | IQR mm |\n|---|---|---|---|\n');
for v = {'lead_cam_takeoff_dist','lead_cam_takeoff_toeoff','trail_cam_takeoff_dist','trail_cam_takeoff_toeoff'}
    x = T.(v{1})(ob);  fprintf(fid, '| `%s` | %d | %.0f | %.0f |\n', v{1}, sum(isfinite(x)), median(x,'omitnan'), iqr(x));
end

% ---------- 13. descriptive medians ----------
fprintf(fid, '\n## Task 13. Descriptive medians (include_ml rows only, cleaned file; no tests)\n\n');
V = {'lead_thigh_max_corr','lead_thigh_rom','trail_shank_min_corr','trail_shank_rom','lead_zhc_peak_foot_h','trail_zhc_peak_foot_h','lead_cam_min_clearance','trail_cam_min_clearance','speed_cross'};
fprintf(fid, '| participant | class | n | %s |\n|%s\n', strjoin(strcat('`', V, '`'), ' | '), repmat('---|', 1, numel(V) + 3));
for p = [P NaN]
    for hc = {'level','H1','H2','H3'}
        if isnan(p), s = inc & strcmp(T.height_class, hc{1}); lab = '**all**';
        else, s = inc & T.participant_id == p & strcmp(T.height_class, hc{1}); lab = num2str(p); end
        vals = cellfun(@(v) num1(median(T.(v)(s), 'omitnan')), V, 'UniformOutput', false);
        fprintf(fid, '| %s | %s | %d | %s |\n', lab, hc{1}, nnz(s), strjoin(vals, ' | '));
    end
end

% ---------- questions ----------
fprintf(fid, ['\n## Questions for you\n\n1. Obstacle heights: what were the real bar heights before and after Test 105 (task 1)? Was the obstacle or its marker mount changed between 104 and 105? ' ...
    'Is the 20 mm marker-to-top offset right for both set-ups?\n' ...
    '2. `order_randomized`: "no" (blocked repeats) or "blocks" (block order counterbalanced between participants)? And please confirm `sex`.\n' ...
    '3. The Dot foot-sensor position on the shoe (distance from the toe tip, height above the sole): with the measured ankle-to-toe length it would let the toe vector be measured instead of fitted (task 3).\n' ...
    '4. Should the drift flag stay in `include_ml`, or should `include_ml_noflag` be the default?\n' ...
    '5. Level rows: add FeatureLog Level_Walk strides as extra level rows (different location definition), or keep the current ones?\n']);
end

function r = rr(a, b)
g = isfinite(a) & isfinite(b);  r = NaN;
if nnz(g) >= 4, c = corrcoef(a(g), b(g)); r = c(1,2); end
end

function s = pct(x)
x = x(isfinite(x));
if isempty(x), s = '-'; else, s = sprintf('%.0f%% (%d/%d)', 100*mean(x), sum(x == 1), numel(x)); end
end

function s = num1(x)
if isfinite(x), s = sprintf('%.1f', x); else, s = '-'; end
end

function s = sgn1(x)
if isfinite(x), s = sprintf('%+.1f', x); else, s = '-'; end
end

function s = sgn0(x)
if isfinite(x), s = sprintf('%+.0f', x); else, s = '-'; end
end

function writeCurves(f, D, CFG)
% Lead and trail swing curves per row (same crossing_id as the dataset), 0:2:100 % swing.
% Tilt in deg (sign-normalized as the _max/_min columns), foot acc |a| in m/s2, ZHC height
% and progression in mm from the begin-ZVP. Empty = not available. FEATURE-type signals (Dot).
pq = round(linspace(0, 100, CFG.curveN));
nm = {};
for L = {'lead','trail'}
    for k = 1:numel(CFG.curveSig)
        nm = [nm, arrayfun(@(v) sprintf('%s_%s_p%03d', L{1}, CFG.curveSig{k}, v), pq, 'UniformOutput', false)]; %#ok<AGROW>
    end
end
T = [D(:, {'crossing_id'}), array2table(round([D.lead_curve, D.trail_curve], 3), 'VariableNames', nm)];
writetable(T, f);
end
