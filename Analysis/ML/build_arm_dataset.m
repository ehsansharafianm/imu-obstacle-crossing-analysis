function build_arm_dataset()
% BUILD_ARM_DATASET  Arm, forearm and trunk kinematics of every obstacle crossing and level walk.
%
%   build_arm_dataset      % about 1 min
%
% READ-ONLY on the pipeline. Inputs (nothing of steps 1-9 is run or changed):
%   Results/Parameters Output/Test N/AllData_TestN.mat          (step 3) Awinda quaternions of the sternum,
%       upper arms and forearms, the OpenSim IK shoulder / elbow angles, the Dot thigh tilt, 60 Hz
%   Results/Parameters Output/Test N/SegmentedParams_TestN.mat  (step 4) ZVP strides, toe-off, heel-strike
%   Results/ML Dataset/Crossing_Master_YoungAdults.csv          (build_crossing_master.m) one row per crossing
%       or level walk: which limb leads and when each limb leaves the floor, clears the obstacle and lands
%
% WHY NOT THE IK ANGLES ALONE. The IK shoulder and elbow angles need the heading of the arm IMUs relative to
% the trunk IMU, and the heading drifts in this laboratory (magnetometer): arm_flex / arm_add wander by tens
% of degrees in half of the participants, elbow_flex sits on its 0 deg limit, and Test 109 has no IK for a
% third of the trial. The IMU quaternions themselves are complete for all ten participants.
%
% HEADING-FREE ANGLES. Only the tilt of each IMU is used, which the heading cannot corrupt:
%   u(t)  = the vertical (up) direction seen in the sensor frame = third row of the rotation matrix
%   u0    = u while standing at the start of the trial (arms hanging) = the long axis of the segment
%   swing axis f (in the sensor frame, perpendicular to u0) = mean displacement of the tilt while the
%           CONTRALATERAL leg swings (toe-off -> heel-strike) during walking: the direction in which the arm
%           travels when it swings forward with the opposite leg. Axis and sign come from the gait events,
%           so a sensor strapped at another angle around the arm gives the same angle.
%   sagittal elevation = atan2(p.f, u.u0),  frontal elevation = atan2(p.m, u.u0), m = u0 x f (abduction +),
%           p = u - (u.u0) u0.  0 deg = the standing posture; + = distal end forward (flexion) / away from the body
%   elbow (planar)     = forearm sagittal elevation - upper-arm sagittal elevation (0 = standing posture)
%   whole arm          = sagittal angle of the shoulder-wrist line (upper arm 0.186, forearm 0.146 of body height)
%   shoulder (planar)  = upper-arm sagittal elevation + trunk pitch = upper arm relative to the trunk; in the
%           frontal plane, abduction to the trunk = frontal elevation -/+ trunk roll (left / right arm)
%   trunk              = sternum IMU, axes from its mounting (sensor z = out of the chest): pitch + = forward
%           lean, roll + = lean towards the right
%
% WINDOWS of a row (crossing or level walk):
%   lead stride  = ZVP -> ZVP stride of the leading foot that holds its swing over the obstacle
%   trail stride = the same for the trailing foot
%   crossing     = leading toe-off -> trailing landing (both swings)
%   arms of a stride: con = arm contralateral to the stride's leg (swings forward with it), ips = ipsilateral;
%   arms of a crossing: ls = arm on the side of the leading limb, ts = arm on the side of the trailing limb
%
% Outputs -> Results/ML Dataset/
%   Arm_Master_YoungAdults.csv   one row per row of the crossing master (same crossing_id, same order)
%   Arm_Curves_YoungAdults.mat   curves per row (stride-normalised, phase-normalised, time-locked to the leading
%                                toe-off), the arm swing of the strides before and after the crossing, and the
%                                median IK and heading-free shoulder angles of every walk of each trial
%   arm_build_report.md          data quality per participant and sensor (IMU and IK)
%   arm_data_dictionary.md       every column of the CSV

here = fileparts(mfilename('fullpath'));
root = fileparts(fileparts(here));
addpath(here);
outDir = fullfile(root, 'Results', 'ML Dataset');
CFG = struct('refS', 2.0, 'walkPad', 2.5, 'hpS', 2.0, 'nNorm', 101, 'lock', (-90:120)' / 60, 'maxStride', 2.5, ...
    'seq', -3:2, 'Lu', 0.186, 'Lf', 0.146, 'lagMax', 0.25, 'phase', [40 20 50 40 40 20]);
t0 = tic;
Dd = mlTools.load(root);  T = Dd.T;  n = height(T);
P = unique(T.participant_id)';

[names, units, defs] = columnSpec();
X = nan(n, numel(names));
CV = initCurves(n, CFG);
QC = struct('tn', {}, 'sensor', {}, 'ik', {}, 'trunk', {}, 'dur', {}, 'rows', {});
for tn = P
    S = loadParticipant(root, tn);
    rows = find(T.participant_id == tn);
    walk = walkMask(S.t, T(rows, :), CFG.walkPad);
    [K, q] = kinematics(S, walk, CFG);
    for r = rows'
        [X(r, :), CV] = rowMeasures(X(r, :), CV, r, T(r, :), S, K, CFG, names);
    end
    CV.trend(end+1) = trendSeries(S, K, walk);
    q.tn = tn;  q.dur = S.t(end) - S.t(1);  q.rows = numel(rows);
    QC(end+1) = q; %#ok<AGROW>
    fprintf('Test %d: %d rows, arm_ok %d, ik_ok %d (%.0f s)\n', tn, numel(rows), nnz(X(rows, strcmp(names, 'arm_ok')) == 1), ...
        nnz(X(rows, strcmp(names, 'ik_ok')) == 1), toc(t0));
end

A = [T(:, {'crossing_id', 'participant_id', 'obstacle_code', 'is_level', 'height_class', 'width_class', 'leading_limb', ...
    'include_biomech'}), array2table(X, 'VariableNames', names)];
writetable(A, fullfile(outDir, 'Arm_Master_YoungAdults.csv'));
CV.crossing_id = T.crossing_id;  CV.cfg = CFG;  CV.qc = QC;
save(fullfile(outDir, 'Arm_Curves_YoungAdults.mat'), '-struct', 'CV');
writeDictionary(fullfile(outDir, 'arm_data_dictionary.md'), names, units, defs);
writeReport(fullfile(outDir, 'arm_build_report.md'), QC, A, CFG);
fprintf('Wrote Arm_Master_YoungAdults.csv (%d rows x %d columns), curves, report and dictionary (%.0f s)\n', n, width(A), toc(t0));
end

%% ========================================================================
%  LOADING
%% ========================================================================
function S = loadParticipant(root, tn)
base = fullfile(root, 'Results', 'Parameters Output', sprintf('Test %d', tn));
d = load(fullfile(base, sprintf('AllData_Test%d.mat', tn)), 'Data');  D = d.Data;
S.tn = tn;  S.t = D.time(:);  S.fs = D.fs;
lab = {D.imu.label};
need = {'ster', 'Sternum (Awinda)'; 'uaL', 'Left Upper Arm (Awinda)'; 'uaR', 'Right Upper Arm (Awinda)'; ...
        'faL', 'Left Forearm (Awinda)'; 'faR', 'Right Forearm (Awinda)'};
for k = 1:size(need, 1)
    i = find(strcmp(lab, need{k,2}), 1);
    assert(~isempty(i), 'Test %d: %s not in AllData', tn, need{k,2});
    S.q.(need{k,1}) = double(D.imu(i).quat);  S.acc.(need{k,1}) = double(D.imu(i).acc);
end
S.thighL = double(D.imu(strcmp(lab, 'Left Thigh (Dot)')).euler_ZXY_deg(:, 2));
S.thighR = double(D.imu(strcmp(lab, 'Right Thigh (Dot)')).euler_ZXY_deg(:, 2));
for j = {'arm_flex', 'arm_add', 'elbow_flex'}
    for sd = 'lr'
        c = find(strcmp(D.joints.labels, [j{1} '_' sd]), 1);
        if isempty(c), S.ik.([j{1} '_' upper(sd)]) = nan(numel(S.t), 1); else, S.ik.([j{1} '_' upper(sd)]) = double(D.joints.angles_deg(:, c)); end
    end
end
d = load(fullfile(base, sprintf('SegmentedParams_Test%d.mat', tn)), 'Seg');  G = d.Seg;
S.zvp = struct('L', G.zvpL(:), 'R', G.zvpR(:));  S.toe = struct('L', G.toeL(:), 'R', G.toeR(:));  S.hs = struct('L', G.hsL(:), 'R', G.hsR(:));
end

function walk = walkMask(t, Tp, pad)
% Samples within the walks that hold a row of the master (leading toe-off - pad ... trailing landing + pad).
walk = false(size(t));
for r = 1:height(Tp)
    a = min([Tp.lead_toeoff_t(r), Tp.trail_toeoff_t(r)], [], 'omitnan');  b = max([Tp.lead_landing_t(r), Tp.trail_landing_t(r)], [], 'omitnan');
    if isfinite(a) && isfinite(b), walk = walk | (t >= a - pad & t <= b + pad); end
end
end

%% ========================================================================
%  HEADING-FREE KINEMATICS OF ONE PARTICIPANT
%% ========================================================================
function [K, q] = kinematics(S, walk, CFG)
fs = S.fs;  nS = numel(S.t);
K = struct();  q = struct('tn', S.tn, 'sensor', struct(), 'ik', struct(), 'trunk', struct(), 'dur', 0, 'rows', 0);
% Dot thigh tilt, forward positive: it rises during the own swing
for sd = 'LR'
    [sg, cons] = swingSign(S.(['thigh' sd]), S.toe.(sd), S.hs.(sd), walk, fs);
    K.(['thigh' sd]) = sg * S.(['thigh' sd]);
    q.sensor.(['thigh' sd]) = struct('swingCons', cons);
end
for sd = 'LR'
    od = other(sd);
    for seg = {'ua', 'fa'}
        key = [seg{1} sd];
        [u, u0, refStd, refAcc] = upVector(S.q.(key), S.acc.(key), fs, CFG.refS);
        c = u * u0';  p = u - c * u0;
        [f, cons, nSw, expl, pcaAng] = swingAxis(p, u0, S.toe.(od), S.hs.(od), walk, fs, CFG.hpS);   % contralateral leg swing
        sag = atan2d(p * f', c);
        m = cross(u0, f);  fro = atan2d(p * m', c);
        if sd == 'R', fro = -fro; end                                           % abduction positive on both sides
        K.([key '_sag']) = sag;  K.([key '_abd']) = fro;
        yExp = [0 1 0] - u0(2) * u0;  yExp = yExp / norm(yExp);                 % sensor y in the tilt plane
        mount = (f * yExp') * sign(u0(1)) * (1 - 2 * (sd == 'R'));              % > 0: forward = +y (left) / -y (right), x up
        q.sensor.(key) = struct('lossPct', 100 * mean(~all(isfinite(S.q.(key)), 2)), 'lossWalk', 100 * mean(~all(isfinite(S.q.(key)(walk, :)), 2)), ...
            'refStd', refStd, 'refAcc', refAcc, 'expl', expl, 'pcaAng', pcaAng, 'swingCons', cons, 'nSwing', nSw, 'mount', mount, 'u0', u0, 'f', f, 'rSeg', NaN);
    end
    K.(['elb' sd]) = K.(['fa' sd '_sag']) - K.(['ua' sd '_sag']);
    hpU = K.(['ua' sd '_sag']) - movmean(K.(['ua' sd '_sag']), round(CFG.hpS * fs), 'omitnan');
    hpF = K.(['fa' sd '_sag']) - movmean(K.(['fa' sd '_sag']), round(CFG.hpS * fs), 'omitnan');
    okS = walk & isfinite(hpU) & isfinite(hpF);
    q.sensor.(['ua' sd]).rSeg = corr(hpU(okS), hpF(okS));  q.sensor.(['fa' sd]).rSeg = q.sensor.(['ua' sd]).rSeg;
    a = K.(['ua' sd '_sag']);  b = K.(['fa' sd '_sag']);
    K.(['arm' sd]) = atan2d(CFG.Lu * sind(a) + CFG.Lf * sind(b), CFG.Lu * cosd(a) + CFG.Lf * cosd(b));
    K.(['vel' sd]) = gradient(movmean(K.(['arm' sd]), 5, 'omitnan')) * fs;      % deg/s
    for j = {'arm_flex', 'arm_add', 'elbow_flex'}
        K.(['ik_' j{1} '_' sd]) = S.ik.([j{1} '_' sd]);
    end
    q.ik.(sd) = ikQuality(S.ik, sd, K, walk, fs);
end
% trunk (sternum): anterior axis = sensor z in the tilt plane
[u, u0, refStd, refAcc] = upVector(S.q.ster, S.acc.ster, fs, CFG.refS);
c = u * u0';  p = u - c * u0;
a = [0 0 1] - u0(3) * u0;  a = a / norm(a);  l = cross(u0, a);
K.tr_pitch = atan2d(-p * a', c);  K.tr_roll = atan2d(p * l', c);
for sd = 'LR', K.(['sh' sd]) = K.(['ua' sd '_sag']) + K.tr_pitch; end        % upper arm relative to the trunk
K.abtL = K.uaL_abd - K.tr_roll;  K.abtR = K.uaR_abd + K.tr_roll;            % the same in the frontal plane: a trunk that leans to
                                                                            % the right carries the left arm outwards, the right one inwards
q.trunk = struct('lossPct', 100 * mean(~all(isfinite(S.q.ster), 2)), 'refStd', refStd, 'refAcc', refAcc, 'u0', u0, ...
    'pitchWalk', median(K.tr_pitch(walk), 'omitnan'), 'rollWalk', median(K.tr_roll(walk), 'omitnan'));
K.n = nS;
end

function [u, u0, refStd, refAcc] = upVector(Q, acc, fs, refS)
% Vertical direction in the sensor frame (third row of the sensor -> global rotation matrix of q = [w x y z])
% and its value while standing at the start (u0). refStd = SD of the inclination from u0 in that window (deg),
% refAcc = mean | |acc| - 9.81 | there (m/s^2): both small when the participant stands still.
w = Q(:,1);  x = Q(:,2);  y = Q(:,3);  z = Q(:,4);
u = [2 * (x .* z - w .* y), 2 * (y .* z + w .* x), 1 - 2 * (x.^2 + y.^2)];
i0 = find(all(isfinite(u), 2), 1);  ref = i0 + (0:round(refS * fs) - 1)';
u0 = median(u(ref, :), 1, 'omitnan');  u0 = u0 / norm(u0);
refStd = std(acosd(max(-1, min(1, u(ref, :) * u0'))), 'omitnan');
refAcc = mean(abs(vecnorm(acc(ref, :), 2, 2) - 9.81), 'omitnan');
end

function [f, cons, nSw, expl, pcaAng] = swingAxis(p, u0, toe, hs, walk, fs, hpS)
% Swing axis of an arm segment in the plane perpendicular to u0: the mean displacement of the tilt p from
% toe-off to the next heel-strike of the CONTRALATERAL foot (walking swings only), so + = the direction in
% which the arm travels when it swings forward. cons = share of the swings that move along it; expl = share
% of the high-passed tilt variance during walking that lies on it; pcaAng = angle (deg) to the first
% principal axis of that tilt (a check: the two agree when the swing dominates the tilt).
d = nan(numel(toe), 3);
for i = 1:numel(toe)
    j = hs(find(hs > toe(i), 1));
    if isempty(j) || j - toe(i) > 1.2 * fs || ~walk(toe(i)) || ~walk(j), continue; end
    d(i, :) = p(j, :) - p(toe(i), :);
end
d = d(all(isfinite(d), 2), :);  nSw = size(d, 1);
f = mean(d, 1);  f = f - (f * u0') * u0;  f = f / norm(f);
cons = mean(d * f' > 0);
e1 = cross(u0, [0 0 1]);
if norm(e1) < 0.2, e1 = cross(u0, [0 1 0]); end
e1 = e1 / norm(e1);  e2 = cross(u0, e1);
hp = p - movmean(p, round(hpS * fs), 1, 'omitnan');
Y = [hp * e1', hp * e2'];  Y = Y(walk & all(isfinite(Y), 2), :);
C = cov(Y);  g = [f * e1', f * e2'];
expl = (g * C * g') / trace(C);
[V, D] = eig(C);  [~, o] = max(diag(D));
pcaAng = acosd(min(1, abs(g * V(:, o))));
end

function [sg, cons, nSw] = swingSign(x, toe, hs, walk, fs)
% Sign that makes x rise from toe-off to the next heel-strike of the given foot (walking swings only),
% and the share of the swings that agree with it.
d = nan(numel(toe), 1);
for i = 1:numel(toe)
    j = hs(find(hs > toe(i), 1));
    if isempty(j) || j - toe(i) > 1.2 * fs || ~walk(toe(i)) || ~walk(j), continue; end
    d(i) = x(j) - x(toe(i));
end
d = d(isfinite(d));  nSw = numel(d);
sg = sign(median(d));  if isempty(d) || sg == 0, sg = 1; end
cons = mean(sign(d) == sg);
end

function q = ikQuality(ik, sd, K, walk, fs)
% Quality indicators of the IK shoulder / elbow angles of one side.
fl = ik.(['arm_flex_' sd]);  ad = ik.(['arm_add_' sd]);  el = ik.(['elbow_flex_' sd]);
ok = walk & isfinite(fl) & isfinite(K.(['ua' sd '_sag']));
hp = @(x) x - movmean(x, round(2 * fs), 'omitnan');
q.nanWalk = 100 * mean(~isfinite(fl(walk)));
q.driftFlex = range30(fl, fs);  q.driftAdd = range30(ad, fs);
q.elbowAtLimit = 100 * mean(el(walk & isfinite(el)) < 0.5);
if nnz(ok) > 100
    a = hp(fl);  b = hp(K.(['ua' sd '_sag']));  c = hp(ad);  d = hp(K.(['ua' sd '_abd']));  e = hp(el);  g = hp(K.(['elb' sd]));
    q.rFlex = corr(a(ok), b(ok));  q.rAdd = corr(-c(ok), d(ok));  q.rElbow = corr(e(ok), g(ok));
    q.rFlexAdd = corr(c(ok), b(ok));                              % swing leaking into the adduction angle
else
    q.rFlex = NaN;  q.rAdd = NaN;  q.rElbow = NaN;  q.rFlexAdd = NaN;
end
end

function r = range30(x, fs)
m = movmedian(x, round(30 * fs), 'omitnan');
r = max(m) - min(m);
end

function s = other(s)
if s == 'L', s = 'R'; else, s = 'L'; end
end

%% ========================================================================
%  MEASURES OF ONE ROW
%% ========================================================================
function [x, CV] = rowMeasures(x, CV, r, Tr, S, K, CFG, names)
ll = Tr.leading_limb{1};
x(strcmp(names, 'arm_ok')) = 0;  x(strcmp(names, 'ik_ok')) = 0;
if isempty(ll), return; end
tl = other(ll);  t = S.t;
st = struct('lead', struct('sd', ll, 'to', Tr.lead_toeoff_t, 'hs', Tr.lead_landing_t, 'apex', Tr.lead_crossing_t_imu), ...
            'trail', struct('sd', tl, 'to', Tr.trail_toeoff_t, 'hs', Tr.trail_landing_t, 'apex', Tr.trail_crossing_t_imu));
ok = true;  ikok = true;
for sn = {'lead', 'trail'}
    s = st.(sn{1});  z = S.zvp.(s.sd);
    c = find(t(z(1:end-1)) <= s.to & s.to < t(z(2:end)), 1);
    if isempty(c) || t(z(c+1)) - t(z(c)) > CFG.maxStride, ok = false; continue; end
    w = (z(c):z(c+1))';  dur = t(w(end)) - t(w(1));
    x = put(x, names, [sn{1} '_stride_dur'], dur);
    th = K.(['thigh' s.sd])(w);
    x = put(x, names, [sn{1} '_thigh_rom'], max(th) - min(th));
    arms = struct('con', other(s.sd), 'ips', s.sd);
    for an = {'con', 'ips'}
        a = arms.(an{1});  pre = [sn{1} '_' an{1} '_'];
        ua = K.(['ua' a '_sag'])(w);  fa = K.(['fa' a '_sag'])(w);  ar = K.(['arm' a])(w);  el = K.(['elb' a])(w);
        ab = K.(['ua' a '_abd'])(w);  ve = K.(['vel' a])(w);  sh = K.(['sh' a])(w);  at = K.(['abt' a])(w);
        if any(~isfinite([ua; fa; sh; at])), ok = false; continue; end
        [amx, imx] = max(ar);
        v = {'ua_rom', max(ua) - min(ua); 'ua_max', max(ua); 'ua_min', min(ua); 'fa_rom', max(fa) - min(fa); 'fa_max', max(fa); ...
             'fa_min', min(fa); 'elb_min', min(el); ...
             'arm_rom', amx - min(ar); 'arm_max', amx; 'arm_min', min(ar); 'elb_rom', max(el) - min(el); 'elb_max', max(el); ...
             'elb_mean', mean(el); 'abd_mean', mean(ab); 'abd_max', max(ab); 'abd_rom', max(ab) - min(ab); 'vel_max', max(ve); ...
             't_max', 100 * (imx - 1) / (numel(w) - 1); 'sh_rom', max(sh) - min(sh); 'sh_max', max(sh); 'sh_min', min(sh); ...
             'sh_mean', mean(sh); 'abt_max', max(at); 'abt_mean', mean(at)};
        for k = 1:size(v, 1), x = put(x, names, [pre v{k,1}], v{k,2}); end
        ikf = K.(['ik_arm_flex_' a])(w);  ika = K.(['ik_arm_add_' a])(w);  ike = K.(['ik_elbow_flex_' a])(w);
        if any(~isfinite([ikf; ika; ike]))
            ikok = false;
        else
            x = put(x, names, [pre 'ik_flex_rom'], max(ikf) - min(ikf));  x = put(x, names, [pre 'ik_add_rom'], max(ika) - min(ika));
            x = put(x, names, [pre 'ik_elb_rom'], max(ike) - min(ike));  x = put(x, names, [pre 'ik_swing_rom'], pcRange([ikf, ika]));
        end
        if strcmp(an{1}, 'con')                                   % coupling of the swinging-forward arm with the leg
            [rr, lag] = xcLag(ar, th, round(CFG.lagMax * numel(w)));
            x = put(x, names, [sn{1} '_cpl_r'], rr);  x = put(x, names, [sn{1} '_cpl_lag'], 100 * lag / (numel(w) - 1));
            x = put(x, names, [sn{1} '_cpl_gain'], (amx - min(ar)) / (max(th) - min(th)));
            tmx = t(w(imx));
            x = put(x, names, [sn{1} '_con_lag_hs'], 1000 * (tmx - s.hs));  x = put(x, names, [sn{1} '_con_lag_apex'], 1000 * (tmx - s.apex));
        end
        CV.(sn{1}).([an{1} '_ua'])(r, :) = resamp(ua, CFG.nNorm);  CV.(sn{1}).([an{1} '_fa'])(r, :) = resamp(fa, CFG.nNorm);
        CV.(sn{1}).([an{1} '_arm'])(r, :) = resamp(ar, CFG.nNorm);  CV.(sn{1}).([an{1} '_elb'])(r, :) = resamp(el, CFG.nNorm);
        CV.(sn{1}).([an{1} '_abd'])(r, :) = resamp(ab, CFG.nNorm);  CV.(sn{1}).([an{1} '_sh'])(r, :) = resamp(sh, CFG.nNorm);
        CV.(sn{1}).([an{1} '_abt'])(r, :) = resamp(at, CFG.nNorm);
        % stride sequence around the crossing stride: arm swing of the strides before and after
        for k = 1:numel(CFG.seq)
            cc = c + CFG.seq(k);
            if cc < 1 || cc + 1 > numel(z), continue; end
            ws = z(cc):z(cc+1);  ds = t(ws(end)) - t(ws(1));
            if ds > 2.0 || ds < 0.6, continue; end
            aa = K.(['arm' a])(ws);
            if all(isfinite(aa)), CV.seq.([sn{1} '_' an{1} '_arm_rom'])(r, k) = max(aa) - min(aa); end
        end
    end
    pt = K.tr_pitch(w);  ro = K.tr_roll(w) * (1 - 2 * (ll == 'L'));              % roll + = towards the leading side
    x = put(x, names, [sn{1} '_trunk_pitch_rom'], max(pt) - min(pt));  x = put(x, names, [sn{1} '_trunk_pitch_max'], max(pt));
    x = put(x, names, [sn{1} '_trunk_pitch_mean'], mean(pt));  x = put(x, names, [sn{1} '_trunk_roll_rom'], max(ro) - min(ro));
    x = put(x, names, [sn{1} '_trunk_roll_mean'], mean(ro));
    CV.(sn{1}).thigh(r, :) = resamp(th, CFG.nNorm);  CV.(sn{1}).pitch(r, :) = resamp(pt, CFG.nNorm);  CV.(sn{1}).roll(r, :) = resamp(ro, CFG.nNorm);
    CV.(sn{1}).toeoff(r) = 100 * (s.to - t(w(1))) / dur;  CV.(sn{1}).landing(r) = 100 * (s.hs - t(w(1))) / dur;
    CV.(sn{1}).apex(r) = 100 * (s.apex - t(w(1))) / dur;
end
% crossing window: leading toe-off -> trailing landing
if isfinite(Tr.lead_toeoff_t) && isfinite(Tr.trail_landing_t) && Tr.trail_landing_t > Tr.lead_toeoff_t && ...
        Tr.trail_landing_t - Tr.lead_toeoff_t < 2 * CFG.maxStride
    w = find(t >= Tr.lead_toeoff_t & t <= Tr.trail_landing_t);
    sides = struct('ls', ll, 'ts', tl);
    for an = {'ls', 'ts'}
        a = sides.(an{1});  pre = ['cw_' an{1} '_'];
        ua = K.(['ua' a '_sag'])(w);  ar = K.(['arm' a])(w);  el = K.(['elb' a])(w);  ab = K.(['ua' a '_abd'])(w);  sh = K.(['sh' a])(w);
        at = K.(['abt' a])(w);
        if any(~isfinite([ua; ar; sh; at])), ok = false; continue; end
        v = {'arm_rom', max(ar) - min(ar); 'ua_rom', max(ua) - min(ua); 'ua_mean', mean(ua); 'ua_max', max(ua); 'ua_min', min(ua); ...
             'elb_max', max(el); 'elb_mean', mean(el); 'abd_max', max(ab); 'abd_mean', mean(ab); 'sh_mean', mean(sh); 'sh_max', max(sh); ...
             'sh_min', min(sh); 'arm_mean', mean(ar); 'abt_max', max(at); 'abt_mean', mean(at)};
        for k = 1:size(v, 1), x = put(x, names, [pre v{k,1}], v{k,2}); end
    end
    pt = K.tr_pitch(w);  ro = K.tr_roll(w) * (1 - 2 * (ll == 'L'));
    x = put(x, names, 'cw_trunk_pitch_rom', max(pt) - min(pt));  x = put(x, names, 'cw_trunk_pitch_max', max(pt));
    x = put(x, names, 'cw_trunk_pitch_mean', mean(pt));  x = put(x, names, 'cw_trunk_roll_rom', max(ro) - min(ro));
    x = put(x, names, 'cw_dur', Tr.trail_landing_t - Tr.lead_toeoff_t);
    [~, ip] = max(pt);                                             % when the trunk leans most
    x = put(x, names, 'cw_trunk_pitch_t_to', 1000 * (t(w(ip)) - Tr.trail_toeoff_t));
    x = put(x, names, 'cw_trunk_pitch_t_ll', 1000 * (t(w(ip)) - Tr.lead_landing_t));
else
    ok = false;
end
% curves around the crossing: time-locked (0 = leading toe-off) and phase-normalised (events aligned)
sides = struct('ls', ll, 'ts', tl);
sig = {'ua', '_sag', 1; 'fa', '_sag', 1; 'arm', '', 0; 'elb', '', 0; 'abd', '_abd', 2; 'sh', '', 0; 'abt', '', 0; 'thigh', '', 0};
if isfinite(Tr.lead_toeoff_t)
    i0 = round(interp1(t, 1:numel(t), Tr.lead_toeoff_t));  idx = i0 + round(CFG.lock * S.fs);
    if ~isnan(i0) && idx(1) >= 1 && idx(end) <= numel(t)
        for an = {'ls', 'ts'}
            for k = 1:size(sig, 1)
                y = K.(sigName(sig(k, :), sides.(an{1})));
                CV.lock.([an{1} '_' sig{k,1}])(r, :) = y(idx);
            end
        end
        CV.lock.pitch(r, :) = K.tr_pitch(idx);  CV.lock.roll(r, :) = K.tr_roll(idx) * (1 - 2 * (ll == 'L'));
        CV.lock.ev(r, :) = [Tr.lead_crossing_t_imu, Tr.lead_landing_t, Tr.trail_toeoff_t, Tr.trail_crossing_t_imu, Tr.trail_landing_t] - Tr.lead_toeoff_t;
    end
end
[tq, anc] = phaseTimes(t, S, ll, tl, Tr, CFG.phase);
CV.phase.anchors(r, :) = anc - Tr.lead_toeoff_t;
if any(isfinite(tq))
    for an = {'ls', 'ts'}
        for k = 1:size(sig, 1)
            CV.phase.([an{1} '_' sig{k,1}])(r, :) = interp1(t, K.(sigName(sig(k, :), sides.(an{1}))), tq);
        end
    end
    CV.phase.pitch(r, :) = interp1(t, K.tr_pitch, tq);  CV.phase.roll(r, :) = interp1(t, K.tr_roll, tq) * (1 - 2 * (ll == 'L'));
end
x(strcmp(names, 'arm_ok')) = double(ok);  x(strcmp(names, 'ik_ok')) = double(ok && ikok);
end

function x = put(x, names, nm, v)
% Writes v into the column nm of the row vector x (error if the column does not exist).
i = find(strcmp(names, nm), 1);
assert(~isempty(i), 'unknown column %s', nm);
x(i) = v;
end

function nm = sigName(sg, side)
% Field of K for a signal row {name, suffix, kind} and a side: kind 1 = <name><side>_sag, 2 = ua<side>_abd, 0 = <name><side>.
switch sg{3}
    case 1,    nm = [sg{1} side sg{2}];
    case 2,    nm = ['ua' side sg{2}];
    otherwise, nm = [sg{1} side];
end
end

function r = pcRange(X)
% Range of the first principal component of the columns of X: the swing, however it is split between the angles.
X = X - mean(X, 1);  [V, D] = eig(cov(X));  [~, o] = max(diag(D));
y = X * V(:, o);  r = max(y) - min(y);
end

function [tq, a] = phaseTimes(t, S, ll, tl, Tr, nPh)
% Sample times of the phase-normalised curves. Anchors (step 4 events): trailing toe-off and heel-strike of the
% step before, leading toe-off, leading landing, trailing toe-off, trailing landing, next leading toe-off.
% Each interval gets a fixed number of points (nPh, about one per 10 ms of its mean duration over all rows),
% so the events of every row fall on the same sample. A segment whose anchors are missing or out of order
% stays NaN.
a = [NaN, NaN, Tr.lead_toeoff_t, Tr.lead_landing_t, Tr.trail_toeoff_t, Tr.trail_landing_t, NaN];
hsT = t(S.hs.(tl));  toT = t(S.toe.(tl));  toL = t(S.toe.(ll));
k = find(hsT < a(3) & a(3) - hsT < 0.6, 1, 'last');
if ~isempty(k)
    a(2) = hsT(k);
    k = find(toT < a(2) & a(2) - toT < 1.2, 1, 'last');
    if ~isempty(k), a(1) = toT(k); end
end
k = find(toL > a(6) & toL - a(6) < 0.6, 1);
if ~isempty(k), a(7) = toL(k); end
tq = nan(1, sum(nPh) + 1);  i0 = 0;
for k = 1:numel(nPh)
    if isfinite(a(k)) && isfinite(a(k+1)) && a(k+1) > a(k) && a(k+1) - a(k) < 2
        x = linspace(a(k), a(k+1), nPh(k) + 1);  tq(i0 + (1:nPh(k) + 1)) = x;
    end
    i0 = i0 + nPh(k);
end
end

function y = resamp(x, n)
y = interp1(linspace(0, 1, numel(x)), x(:)', linspace(0, 1, n));
end

function [r, lag] = xcLag(a, b, L)
% Largest normalised cross-correlation of a (arm) with b (thigh) for lags -L..L samples; lag > 0 = the arm follows.
a = a(:) - mean(a);  b = b(:) - mean(b);  n = numel(a);  best = -inf;  r = NaN;  lag = NaN;
for k = -L:L
    if k >= 0, x = a(1+k:n);  y = b(1:n-k); else, x = a(1:n+k);  y = b(1-k:n); end
    v = (x' * y) / sqrt((x' * x) * (y' * y));
    if v > best, best = v;  r = v;  lag = k; end
end
end

function CV = initCurves(n, CFG)
nn = CFG.nNorm;  nl = numel(CFG.lock);  ns = numel(CFG.seq);  np = sum(CFG.phase) + 1;
for sn = {'lead', 'trail'}
    for an = {'con', 'ips'}
        for sg = {'ua', 'fa', 'arm', 'elb', 'abd', 'sh', 'abt'}
            CV.(sn{1}).([an{1} '_' sg{1}]) = nan(n, nn);
        end
        CV.seq.([sn{1} '_' an{1} '_arm_rom']) = nan(n, ns);
    end
    CV.(sn{1}).thigh = nan(n, nn);  CV.(sn{1}).pitch = nan(n, nn);  CV.(sn{1}).roll = nan(n, nn);
    CV.(sn{1}).toeoff = nan(n, 1);  CV.(sn{1}).landing = nan(n, 1);  CV.(sn{1}).apex = nan(n, 1);
end
for an = {'ls', 'ts'}
    for sg = {'ua', 'fa', 'arm', 'elb', 'abd', 'sh', 'abt', 'thigh'}
        CV.lock.([an{1} '_' sg{1}]) = nan(n, nl);  CV.phase.([an{1} '_' sg{1}]) = nan(n, np);
    end
end
CV.lock.pitch = nan(n, nl);  CV.lock.roll = nan(n, nl);  CV.lock.ev = nan(n, 5);
CV.phase.pitch = nan(n, np);  CV.phase.roll = nan(n, np);  CV.phase.anchors = nan(n, 7);
CV.phase.n = CFG.phase;  CV.phase.x = 0:sum(CFG.phase);
CV.lock.t = CFG.lock;  CV.pct = linspace(0, 100, nn);  CV.seq.k = CFG.seq;
CV.trend = struct('tn', {}, 't', {}, 'ik_flex', {}, 'ik_add', {}, 'sag', {}, 'abd', {});
end

function R = trendSeries(S, K, walk)
% Slow trend of the shoulder angles over the trial: the median of each walk (a run of walking samples: one pass
% over the walkway) of the IK arm_flex / arm_add and of their heading-free counterparts (columns = left, right
% arm). A walking posture does not wander by tens of degrees from one pass to the next; heading drift does.
d = diff([false; walk(:); false]);  a = find(d == 1);  b = find(d == -1) - 1;
med = @(x) arrayfun(@(i) median(x(a(i):b(i)), 'omitnan'), (1:numel(a))');
R.tn = S.tn;  R.t = (S.t(a) + S.t(b)) / 2;
R.ik_flex = [med(K.ik_arm_flex_L), med(K.ik_arm_flex_R)];  R.ik_add = [med(K.ik_arm_add_L), med(K.ik_arm_add_R)];
R.sag = [med(K.shL), med(K.shR)];  R.abd = [med(K.abtL), med(K.abtR)];
end

%% ========================================================================
%  COLUMNS
%% ========================================================================
function [names, units, defs] = columnSpec()
C = {'arm_ok', '0/1', '1 = both crossing strides found (ZVP stride <= 2.5 s), the crossing window is defined and no arm IMU sample is missing in them.';
     'ik_ok', '0/1', '1 = arm_ok and the IK shoulder / elbow angles of both arms are present in both strides.'};
stride = {'lead', 'ZVP -> ZVP stride of the LEADING foot that holds its swing over the obstacle (level row: the foot that passes y = 0 first)'; ...
          'trail', 'ZVP -> ZVP stride of the TRAILING foot that holds its swing over the obstacle'};
arm = {'con', 'arm CONTRALATERAL to the leg of this stride (it swings forward with that leg)'; 'ips', 'arm IPSILATERAL to the leg of this stride'};
M = {'ua_rom', 'deg', 'Upper-arm sagittal elevation, max - min over the stride (heading-free IMU tilt; 0 = standing posture, + = forward).';
     'ua_max', 'deg', 'Upper-arm sagittal elevation, maximum (peak forward swing / shoulder flexion).';
     'ua_min', 'deg', 'Upper-arm sagittal elevation, minimum (peak backward swing / shoulder extension; negative = behind the standing posture).';
     'fa_rom', 'deg', 'Forearm sagittal elevation, max - min.';
     'fa_max', 'deg', 'Forearm sagittal elevation, maximum (peak forward).';
     'fa_min', 'deg', 'Forearm sagittal elevation, minimum (peak backward).';
     'elb_min', 'deg', 'Planar elbow flexion, minimum over the stride (most extended), relative to the standing posture.';
     'arm_rom', 'deg', 'Whole-arm swing: sagittal angle of the shoulder-wrist line (upper arm 0.186, forearm 0.146 of body height), max - min.';
     'arm_max', 'deg', 'Whole-arm sagittal angle, maximum (forward).';
     'arm_min', 'deg', 'Whole-arm sagittal angle, minimum (backward).';
     'elb_rom', 'deg', 'Planar elbow flexion (forearm - upper-arm sagittal elevation), max - min.';
     'elb_max', 'deg', 'Planar elbow flexion, maximum, relative to the standing posture.';
     'elb_mean', 'deg', 'Planar elbow flexion, mean over the stride.';
     'abd_mean', 'deg', 'Upper-arm frontal elevation (abduction +, away from the body), mean over the stride, relative to the standing posture.';
     'abd_max', 'deg', 'Upper-arm frontal elevation, maximum.';
     'abd_rom', 'deg', 'Upper-arm frontal elevation, max - min.';
     'vel_max', 'deg/s', 'Peak forward angular velocity of the whole-arm sagittal angle (5-sample moving average, central difference).';
     't_max', '% stride', 'Time of the whole-arm maximum (peak forward swing) in the stride, 0 = begin-ZVP, 100 = end-ZVP.';
     'sh_rom', 'deg', 'Upper arm relative to the trunk (planar shoulder flexion = upper-arm sagittal elevation + trunk pitch), max - min.';
     'sh_max', 'deg', 'Upper arm relative to the trunk, maximum (shoulder flexion; 0 = standing posture).';
     'sh_min', 'deg', 'Upper arm relative to the trunk, minimum (shoulder extension).';
     'sh_mean', 'deg', 'Upper arm relative to the trunk, mean over the stride.';
     'abt_max', 'deg', 'Abduction relative to the trunk (upper-arm frontal elevation minus the trunk roll that carries the arm), maximum.';
     'abt_mean', 'deg', 'Abduction relative to the trunk, mean over the stride.';
     'ik_flex_rom', 'deg', 'OpenSim IK arm_flex (shoulder flexion), max - min over the stride. Heading-dependent: see arm_build_report.md.';
     'ik_add_rom', 'deg', 'OpenSim IK arm_add (shoulder adduction), max - min. Heading-dependent.';
     'ik_elb_rom', 'deg', 'OpenSim IK elbow_flex, max - min. Clamped at its 0 deg limit in most participants.';
     'ik_swing_rom', 'deg', 'OpenSim IK shoulder swing: range of the first principal component of (arm_flex, arm_add) in the stride, i.e. the swing however the heading splits it between the two angles.'};
for s = 1:2
    for a = 1:2
        for k = 1:size(M, 1)
            C(end+1, :) = {[stride{s,1} '_' arm{a,1} '_' M{k,1}], M{k,2}, sprintf('%s Window: %s; %s.', M{k,3}, stride{s,2}, arm{a,2})}; %#ok<AGROW>
        end
    end
    R = {'stride_dur', 's', 'Duration of the stride (ZVP -> ZVP).';
         'thigh_rom', 'deg', 'Dot thigh tilt of the leg of this stride (forward +), max - min.';
         'cpl_r', '-', 'Arm-leg coupling: largest normalised cross-correlation of the whole-arm angle of the contralateral arm with the thigh tilt of this leg, lags within 25 % of the stride.';
         'cpl_lag', '% stride', 'Lag at that maximum (+ = the arm follows the thigh).';
         'cpl_gain', 'deg/deg', 'Whole-arm swing of the contralateral arm / thigh range of this leg.';
         'con_lag_hs', 'ms', 'Time of the contralateral arm''s peak forward swing minus the landing (heel-strike) of this leg (- = the arm peaks before the foot lands).';
         'con_lag_apex', 'ms', 'Time of the contralateral arm''s peak forward swing minus the foot apex of this leg (the moment it clears the obstacle).';
         'trunk_pitch_rom', 'deg', 'Trunk (sternum IMU) pitch, max - min over the stride.';
         'trunk_pitch_max', 'deg', 'Trunk pitch, maximum (forward lean +, 0 = standing posture).';
         'trunk_pitch_mean', 'deg', 'Trunk pitch, mean over the stride.';
         'trunk_roll_rom', 'deg', 'Trunk roll, max - min.';
         'trunk_roll_mean', 'deg', 'Trunk roll, mean (+ = lean towards the side of the leading limb).'};
    for k = 1:size(R, 1)
        C(end+1, :) = {[stride{s,1} '_' R{k,1}], R{k,2}, sprintf('%s Window: %s.', R{k,3}, stride{s,2})}; %#ok<AGROW>
    end
end
side = {'ls', 'arm on the side of the LEADING limb'; 'ts', 'arm on the side of the TRAILING limb'};
W = {'arm_rom', 'deg', 'Whole-arm sagittal angle, max - min.'; 'ua_rom', 'deg', 'Upper-arm sagittal elevation, max - min.';
     'ua_mean', 'deg', 'Upper-arm sagittal elevation, mean (posture of the arm during the crossing).';
     'ua_max', 'deg', 'Upper-arm sagittal elevation, maximum.'; 'ua_min', 'deg', 'Upper-arm sagittal elevation, minimum.';
     'elb_max', 'deg', 'Planar elbow flexion, maximum.'; 'elb_mean', 'deg', 'Planar elbow flexion, mean.';
     'abd_max', 'deg', 'Upper-arm frontal elevation (abduction +), maximum.'; 'abd_mean', 'deg', 'Upper-arm frontal elevation, mean.';
     'sh_mean', 'deg', 'Upper arm relative to the trunk (upper-arm sagittal elevation + trunk pitch), mean.';
     'sh_max', 'deg', 'Upper arm relative to the trunk, maximum.'; 'sh_min', 'deg', 'Upper arm relative to the trunk, minimum.';
     'arm_mean', 'deg', 'Whole-arm sagittal angle, mean.';
     'abt_max', 'deg', 'Abduction relative to the trunk, maximum.'; 'abt_mean', 'deg', 'Abduction relative to the trunk, mean.'};
for a = 1:2
    for k = 1:size(W, 1)
        C(end+1, :) = {['cw_' side{a,1} '_' W{k,1}], W{k,2}, sprintf('%s Window: crossing (leading toe-off -> trailing landing); %s.', W{k,3}, side{a,2})}; %#ok<AGROW>
    end
end
C = [C; {'cw_trunk_pitch_rom', 'deg', 'Trunk pitch, max - min over the crossing window.';
         'cw_trunk_pitch_max', 'deg', 'Trunk pitch, maximum over the crossing window (forward lean +).';
         'cw_trunk_pitch_mean', 'deg', 'Trunk pitch, mean over the crossing window.';
         'cw_trunk_roll_rom', 'deg', 'Trunk roll, max - min over the crossing window.';
         'cw_dur', 's', 'Duration of the crossing window (leading toe-off -> trailing landing).';
         'cw_trunk_pitch_t_to', 'ms', 'Time of the largest trunk forward lean in the crossing window minus the trailing toe-off (step 4 event).';
         'cw_trunk_pitch_t_ll', 'ms', 'Time of the largest trunk forward lean in the crossing window minus the leading landing.'}];
names = C(:, 1)';  units = C(:, 2)';  defs = C(:, 3)';
end

%% ========================================================================
%  REPORT AND DICTIONARY
%% ========================================================================
function writeDictionary(f, names, units, defs)
L = {};
L = addl(L, '# Data dictionary: Arm_Master_YoungAdults.csv');
L = addl(L, '');
L = addl(L, '_Generated by `Analysis/ML/build_arm_dataset.m` on %s._', char(datetime('now', 'Format', 'yyyy-MM-dd HH:mm')));
L = addl(L, '');
L = addl(L, ['One row per row of `Crossing_Master_YoungAdults.csv` (same `crossing_id`, same order; identifier and label columns copied ' ...
    'from it). All angles come from the tilt of the Awinda IMUs (heading-free, see the header of `build_arm_dataset.m`) unless the name ' ...
    'starts with `ik_`. Empty cell = not computed (never imputed).']);
L = addl(L, '');
L = addl(L, '| # | name | unit | definition |');
L = addl(L, '|---|---|---|---|');
for k = 1:numel(names), L = addl(L, '| %d | `%s` | %s | %s |', k, names{k}, units{k}, defs{k}); end
writeLines(f, L);
end

function writeReport(f, QC, A, CFG)
L = {};
L = addl(L, '# Build report: Arm_Master_YoungAdults');
L = addl(L, '');
L = addl(L, '_Generated by `Analysis/ML/build_arm_dataset.m` on %s._', char(datetime('now', 'Format', 'yyyy-MM-dd HH:mm')));
L = addl(L, '');
L = addl(L, '## 1. Rows');
L = addl(L, '');
L = addl(L, '| participant | rows | arm_ok | ik_ok | include_biomech and arm_ok | include_biomech and ik_ok |');
L = addl(L, '|---|---|---|---|---|---|');
for q = QC
    i = A.participant_id == q.tn;
    L = addl(L, '| %d | %d | %d | %d | %d | %d |', q.tn, nnz(i), nnz(i & A.arm_ok == 1), nnz(i & A.ik_ok == 1), ...
        nnz(i & A.arm_ok == 1 & A.include_biomech == 1), nnz(i & A.ik_ok == 1 & A.include_biomech == 1));
end
L = addl(L, '| all | %d | %d | %d | %d | %d |', height(A), nnz(A.arm_ok == 1), nnz(A.ik_ok == 1), nnz(A.arm_ok == 1 & A.include_biomech == 1), ...
    nnz(A.ik_ok == 1 & A.include_biomech == 1));
L = addl(L, '');
L = addl(L, '## 2. Arm IMUs (Awinda): data loss, standing reference, swing plane');
L = addl(L, '');
L = addl(L, ['loss = samples without a quaternion (whole trial / inside the walks that hold a row); reference = first %.0f s of the trial: SD of ' ...
    'the inclination (deg) and mean | |acc| - 9.81 | (m/s^2), both near 0 when the participant stands still; swing axis = mean displacement of ' ...
    'the tilt while the contralateral leg swings: share of the swings (n) that move along it, share of the walking tilt variance that lies on ' ...
    'it (plane), and its angle to the first principal axis of that tilt (PCA, deg); upper arm - forearm r = correlation of the two sagittal ' ...
    'elevations of the same arm during walking (2 s high-pass; they swing together); mounting = cosine between the forward axis found from the ' ...
    'data and the one expected from the sensor mounting (x along the segment, z out of the strap: + y on the left arm, - y on the right).'], CFG.refS);
L = addl(L, '');
L = addl(L, '| participant | sensor | loss %% (trial / walks) | reference SD (deg) / acc | swings along the axis (n) | plane | PCA (deg) | upper arm - forearm r | mounting |');
L = addl(L, '|---|---|---|---|---|---|---|---|---|');
nm = {'uaL', 'left upper arm'; 'uaR', 'right upper arm'; 'faL', 'left forearm'; 'faR', 'right forearm'};
allS = [];
for q = QC
    for k = 1:size(nm, 1)
        s = q.sensor.(nm{k,1});  allS = [allS, s]; %#ok<AGROW>
        L = addl(L, '| %d | %s | %.2f / %.2f | %.2f / %.2f | %.0f %% (%d) | %.2f | %.0f | %+.2f | %+.2f |', q.tn, nm{k,2}, s.lossPct, s.lossWalk, ...
            s.refStd, s.refAcc, 100 * s.swingCons, s.nSwing, s.expl, s.pcaAng, s.rSeg, s.mount);
    end
end
L = addl(L, '');
L = addl(L, ['**Reading.** Data loss inside the walks: %.2f %% at most. Standing reference: inclination SD %.2f deg at most. The contralateral-leg ' ...
    'swings move along the swing axis in %.0f-%.0f %% of the cases (median %.0f %%); upper arm and forearm of the same arm swing together (r %.2f ' ...
    'to %.2f); %d of %d sensors agree with the mounting convention (the others are strapped at another angle around the arm, which the ' ...
    'data-driven axis absorbs).'], max([allS.lossWalk]), max([allS.refStd]), 100 * min([allS.swingCons]), 100 * max([allS.swingCons]), ...
    100 * median([allS.swingCons]), min([allS.rSeg]), max([allS.rSeg]), nnz([allS.mount] > 0.5), numel(allS));
L = addl(L, '');
L = addl(L, '## 3. Trunk IMU (sternum)');
L = addl(L, '');
L = addl(L, '| participant | loss %% | reference SD (deg) / acc | sensor z vs vertical (deg) | median pitch during the walks (deg) | median roll (deg) |');
L = addl(L, '|---|---|---|---|---|---|');
for q = QC
    s = q.trunk;
    L = addl(L, '| %d | %.2f | %.2f / %.2f | %.0f | %+.1f | %+.1f |', q.tn, s.lossPct, s.refStd, s.refAcc, acosd(s.u0(3)), s.pitchWalk, s.rollWalk);
end
L = addl(L, '');
L = addl(L, ['Sensor z vs vertical below 90 deg = the outward normal of the sensor points forward and up, as expected on the sternum (pitch + = ' ...
    'forward lean rests on this mounting).']);
L = addl(L, '');
L = addl(L, '## 4. OpenSim IK shoulder and elbow angles');
L = addl(L, '');
L = addl(L, ['missing = share of the walking samples without IK; drift = range of the 30 s moving median over the trial (deg; a posture ' ...
    'does not wander this much, heading drift does); elbow at limit = share of the walking samples with elbow_flex < 0.5 deg (the model ' ...
    'limit is 0); r = correlation during walking (2 s high-pass) of the IK angle with its heading-free counterpart: arm_flex with the upper-arm ' ...
    'sagittal elevation, - arm_add with the frontal elevation, elbow_flex with the planar elbow angle; leak = correlation of arm_add with the ' ...
    'sagittal elevation (swing that leaked into the adduction angle).']);
L = addl(L, '');
L = addl(L, '| participant | side | missing %% | drift arm_flex / arm_add (deg) | elbow at limit %% | r arm_flex | r arm_add | r elbow | leak |');
L = addl(L, '|---|---|---|---|---|---|---|---|---|');
for q = QC
    for sd = 'LR'
        s = q.ik.(sd);
        L = addl(L, '| %d | %s | %.1f | %.0f / %.0f | %.0f | %+.2f | %+.2f | %+.2f | %+.2f |', q.tn, sd, s.nanWalk, s.driftFlex, s.driftAdd, s.elbowAtLimit, ...
            s.rFlex, s.rAdd, s.rElbow, s.rFlexAdd);
    end
end
L = addl(L, '');
I = arrayfun(@(q) [q.ik.L, q.ik.R], QC, 'UniformOutput', false);  I = [I{:}];
L = addl(L, ['**Reading.** IK missing during the walks in %d of %d participant sides; drift of arm_flex above 20 deg in %d of %d; elbow_flex on its ' ...
    'limit for more than half of the walking samples in %d of %d; arm_flex follows the heading-free swing with |r| > 0.7 in %d of %d and has ' ...
    'the opposite sign in %d.'], nnz([I.nanWalk] > 0), numel(I), nnz([I.driftFlex] > 20), numel(I), nnz([I.elbowAtLimit] > 50), numel(I), ...
    nnz(abs([I.rFlex]) > 0.7), numel(I), nnz([I.rFlex] < 0));
writeLines(f, L);
end

function L = addl(L, fmt, varargin)
if isempty(varargin), L{end+1} = strrep(fmt, '%%', '%'); else, L{end+1} = sprintf(fmt, varargin{:}); end
end

function writeLines(f, L)
fid = fopen(f, 'w', 'n', 'UTF-8');  assert(fid > 0, 'cannot open %s', f);
c = onCleanup(@() fclose(fid));
fprintf(fid, '%s\n', L{:});
end
