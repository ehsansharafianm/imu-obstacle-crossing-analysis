clc
close all
addpath(fileparts(mfilename('fullpath')));

%% ========================================================================
%% STEP 4 - Gait events (toe-off / ZVP) + stride segmentation
%% ========================================================================
% Loads Data (step 3), detects ZVP per side from that side's DOT FOOT IMU,
% and segments every signal into strides normalized to the gait cycle.
%   1) toe-offs   = inverted minima of the foot roll angle,
%   2) candidates = low |gyro| AND low |acc| (flat foot),
%   3) one ZVP between consecutive toe-offs (midpoint of the candidates),
%   4) cut each signal at its side's ZVPs and time-normalize to NSEG points.
% LEFT signals -> Left Foot (Dot) ZVPs; RIGHT -> Right Foot (Dot);
% Pelvis & Sternum (Awinda) -> LEFT foot ZVPs.

%% ===================== DETECTION SETTINGS =====================
MIN_PROMINENCE = 15;   % deg, prominence for toe-off / heel-strike peaks
MIN_PEAK_DIST  = 15;   % samples, min distance between toe-offs
OMEGA_THRESH   = 24;   % |gyro| candidate threshold (sensor unit, ~deg/s)
ACC_THRESH     = 21;   % |acc|  candidate threshold (m/s^2, incl. gravity)

% Roll-angle axis per foot: X (column 2) for both. (1=Z,2=X,3=Y; 0=auto.)
ROLL_COL_L = 2;   ROLL_SIGN_L = 1;
ROLL_COL_R = 2;   ROLL_SIGN_R = 1;

% Stride segmentation
NSEG   = 200;          % samples per normalized stride (0-100% gait cycle)
INTERP = 'spline';     % interpolation onto the normalized grid
ZVP_SKIP_START = 2;    % drop this many leading ZVPs (start after them)

%% ===================== APPEARANCE SETTINGS =====================
FONT_NAME  = 'Arial';  TITLE_SIZE = 15;  LABEL_SIZE = 13;  TICK_SIZE = 11;
LINE_WIDTH = 1.6;
COL_ANGLE  = [0.10 0.40 0.85];  COL_OMEGA = [0.85 0.30 0.10];
COL_ACC    = [0.20 0.65 0.20];  COL_ZVP   = [0.90 0.10 0.10];
COL_TOE    = [0.20 0.60 0.20];  COL_HS    = [0.60 0.20 0.70];

%% ===================== LOAD DATA =====================
tn = input('  Input Test Number: ');
% Anchor to the script's own folder (parent of Analysis holds Results), so this
% works regardless of the current MATLAB folder; fall back to cwd-relative.
root = fileparts(fileparts(mfilename('fullpath')));
base = fullfile(root, 'Results','Parameters Output', ['Test ' num2str(tn)]);
matFile = fullfile(base, sprintf('AllData_Test%d.mat', tn));
if ~isfile(matFile)
    base2 = fullfile('..','Results','Parameters Output', ['Test ' num2str(tn)]);
    mf2   = fullfile(base2, sprintf('AllData_Test%d.mat', tn));
    if isfile(mf2), base = base2; matFile = mf2; end
end
if ~isfile(matFile), error('Not found: %s  (run step 3 for Test %d first).', matFile, tn); end
load(matFile, 'Data');
t = Data.time;

iL = find(strcmp({Data.imu.label}, 'Left Foot (Dot)'),  1);
iR = find(strcmp({Data.imu.label}, 'Right Foot (Dot)'), 1);
if isempty(iL) || isempty(iR), error('Left/Right Foot (Dot) not found in Data.imu.'); end

%% ===================== ROLL ANGLE PER FOOT =====================
axName = {'Z','X','Y'};
EL = Data.imu(iL).euler_ZXY_deg;
ER = Data.imu(iR).euler_ZXY_deg;
if ROLL_COL_L == 0, colL = pickAxis(EL); else, colL = ROLL_COL_L; end
if ROLL_COL_R == 0, colR = pickAxis(ER); else, colR = ROLL_COL_R; end
rollL = ROLL_SIGN_L * EL(:, colL);
rollR = ROLL_SIGN_R * ER(:, colR);

%% ===================== DETECT GAIT EVENTS + ZVP =====================
[toeL, hsL, ~, zvpL, omL, accL] = detectGaitEvents(rollL, Data.imu(iL).gyro, Data.imu(iL).acc, ...
                                   MIN_PROMINENCE, MIN_PEAK_DIST, OMEGA_THRESH, ACC_THRESH);
[toeR, hsR, ~, zvpR, omR, accR] = detectGaitEvents(rollR, Data.imu(iR).gyro, Data.imu(iR).acc, ...
                                   MIN_PROMINENCE, MIN_PEAK_DIST, OMEGA_THRESH, ACC_THRESH);

% Drop leading ZVP(s) so segmentation starts at a consistent stride.
if numel(zvpL) > ZVP_SKIP_START, zvpL = zvpL(ZVP_SKIP_START+1:end); end
if numel(zvpR) > ZVP_SKIP_START, zvpR = zvpR(ZVP_SKIP_START+1:end); end

fprintf('\n=== Gait events (Test %d) ===\n', Data.test);
fprintf('  Left  (roll %s): %d toe-offs, %d ZVP\n', axName{colL}, numel(toeL), numel(zvpL));
fprintf('  Right (roll %s): %d toe-offs, %d ZVP\n', axName{colR}, numel(toeR), numel(zvpR));

%% ===================== FIGURE 1 - ZVP DETECTION =====================
figure('Color','w','Name',sprintf('Step 4 - ZVP  |  Test %d', Data.test), 'Position',[80 80 1320 770]);
sd = {FONT_NAME, TITLE_SIZE, LABEL_SIZE, TICK_SIZE, LINE_WIDTH};
drawSide(subplot(2,2,1), t, rollL, toeL, hsL, zvpL, ...
         sprintf('Left Foot (Dot) - roll (%s) & events', axName{colL}), COL_ANGLE, COL_TOE, COL_HS, COL_ZVP, sd);
drawNorms(subplot(2,2,2), t, omL, accL, zvpL, OMEGA_THRESH, ACC_THRESH, ...
          'Left Foot (Dot) - detection norms', COL_OMEGA, COL_ACC, COL_ZVP, sd);
drawSide(subplot(2,2,3), t, rollR, toeR, hsR, zvpR, ...
         sprintf('Right Foot (Dot) - roll (%s) & events', axName{colR}), COL_ANGLE, COL_TOE, COL_HS, COL_ZVP, sd);
drawNorms(subplot(2,2,4), t, omR, accR, zvpR, OMEGA_THRESH, ACC_THRESH, ...
          'Right Foot (Dot) - detection norms', COL_OMEGA, COL_ACC, COL_ZVP, sd);

%% ===================== STRIDE SEGMENTATION =====================
pct = linspace(0, 100, NSEG)';
segT = {}; segY = {}; segL = {};
for i = 1:numel(Data.imu)            % IMUs: X angle only (Y = NSEG x nStrides)
    zvp = sideZVP(zvpSideIMU(Data.imu(i).label), zvpL, zvpR);
    segY{end+1} = segmentAll(t, Data.imu(i).euler_ZXY_deg(:,2), zvp, NSEG, INTERP); %#ok<SAGROW>
    segT{end+1} = pct;                                                              %#ok<SAGROW>
    segL{end+1} = sprintf('IMU: %s X', Data.imu(i).label);                          %#ok<SAGROW>
end
for j = 1:numel(Data.joints.labels) % joints (excluding hip rotation)
    nm  = Data.joints.labels{j};
    if contains(nm,'hip_rotation'), continue; end
    zvp = sideZVP(zvpSideJoint(nm), zvpL, zvpR);
    segY{end+1} = segmentAll(t, Data.joints.angles_deg(:,j), zvp, NSEG, INTERP); %#ok<SAGROW>
    segT{end+1} = pct;                                                           %#ok<SAGROW>
    segL{end+1} = sprintf('Joint: %s', nm);                                      %#ok<SAGROW>
end
fprintf('Segmented %d signals to %d points (Left %d strides, Right %d strides).\n', ...
        numel(segL), NSEG, max(numel(zvpL)-1,0), max(numel(zvpR)-1,0));

% --- Time-domain (non-normalized) strides: same ZVP cycles, raw samples,
%     NaN-padded to the longest stride; time axis relative (0 s at each start).
dt     = median(diff(t));
maxLen = max([strideMax(zvpL), strideMax(zvpR), 1]);
tvec   = (0:maxLen-1)' * dt;
segYt = {};  segTt = {};
for i = 1:numel(Data.imu)
    zvp = sideZVP(zvpSideIMU(Data.imu(i).label), zvpL, zvpR);
    segYt{end+1} = segmentAllTime(Data.imu(i).euler_ZXY_deg(:,2), zvp, maxLen); %#ok<SAGROW>
    segTt{end+1} = tvec;                                                        %#ok<SAGROW>
end
for j = 1:numel(Data.joints.labels)
    nm = Data.joints.labels{j};
    if contains(nm,'hip_rotation'), continue; end
    zvp = sideZVP(zvpSideJoint(nm), zvpL, zvpR);
    segYt{end+1} = segmentAllTime(Data.joints.angles_deg(:,j), zvp, maxLen); %#ok<SAGROW>
    segTt{end+1} = tvec;                                                     %#ok<SAGROW>
end

%% ===================== ZHC FOOT TRAJECTORY (both feet) =====================
% Trajectory reconstruction with the reference pipeline, ported verbatim:
%   quaternion -> Euler:  fliplr(rad2deg(quat2eul(q,'ZYX')))       (processIMUQuaternion)
%   rotation:             Rz(yaw)*Ry(pitch)*Rx(roll)               (RotationMatrix_fcn)
%   trajectory:           ZHC_Method_Function, level-ground branch (gain_hs = 1,
%                         k_hs_selected = 0, heel-strike velocity at stride start)
% Windows = the step-4 ZVP cycles (same as realZUPTIndices). Requires the raw
% quaternion saved by step 3 (Data.imu(k).quat) - re-run step 3 if missing.
zhcOK = isfield(Data.imu, 'quat') && ~isempty(Data.imu(iL).quat) && ~isempty(Data.imu(iR).quat);
if zhcOK
    GRAVITY = 9.80665;
    eulL = fliplr(rad2deg(quat2eul(Data.imu(iL).quat, 'ZYX')));   % [roll pitch yaw] deg
    eulR = fliplr(rad2deg(quat2eul(Data.imu(iR).quat, 'ZYX')));
    RML  = rotationMatrixRef(eulL);                               % Rz*Ry*Rx per sample
    RMR  = rotationMatrixRef(eulR);
    [zhcTimeL, zhcGaitL, tContL, pContL, tZvpL, pZvpL] = zhcRef(Data.imu(iL).acc, t, zvpL, RML, NSEG, maxLen, GRAVITY);
    [zhcTimeR, zhcGaitR, tContR, pContR, tZvpR, pZvpR] = zhcRef(Data.imu(iR).acc, t, zvpR, RMR, NSEG, maxLen, GRAVITY);
    fprintf('ZHC trajectories: Left %d windows, Right %d windows.\n', size(zhcTimeL,3), size(zhcTimeR,3));
else
    warning('Data.imu has no quaternion (.quat) - re-run step 3 to enable the ZHC trajectory.');
end

%% ===================== SAVE SEGMENTATION RESULTS =====================
% Tidy struct with every signal's strides (points), mean, and SD (shade).
Seg = struct();
Seg.test = Data.test;  Seg.fs = Data.fs;  Seg.nseg = NSEG;  Seg.pct = pct;
Seg.zvpL = zvpL;       Seg.zvpR = zvpR;
Seg.dt = dt;           Seg.timeAxis = tvec;            % time-domain x-axis (s)
Seg.signal = struct('label',{},'type',{},'side',{},'strides',{},'mean',{},'sd',{}, ...
                    'nStrides',{},'stridesTime',{},'meanTime',{},'sdTime',{});
for k = 1:numel(segL)
    Yk = segY{k};  Ykt = segYt{k};
    if startsWith(segL{k},'Joint:')
        ty = 'Joint';  if endsWith(segL{k},'_r'), sd_ = 'R'; else, sd_ = 'L'; end
    else
        ty = 'IMU';    if contains(segL{k},'Right'), sd_ = 'R'; else, sd_ = 'L'; end
    end
    Seg.signal(k).label       = segL{k};
    Seg.signal(k).type        = ty;
    Seg.signal(k).side        = sd_;
    Seg.signal(k).strides     = Yk;                        % NSEG x nStrides (normalized)
    Seg.signal(k).mean        = mean(Yk, 2, 'omitnan');    % NSEG x 1
    Seg.signal(k).sd          = std(Yk, 0, 2, 'omitnan');  % NSEG x 1 (shade)
    Seg.signal(k).nStrides    = size(Yk, 2);
    Seg.signal(k).stridesTime = Ykt;                       % maxLen x nStrides (raw, time; NaN-padded)
    Seg.signal(k).meanTime    = mean(Ykt, 2, 'omitnan');   % maxLen x 1
    Seg.signal(k).sdTime      = std(Ykt, 0, 2, 'omitnan'); % maxLen x 1
end
if zhcOK
    % ZHC foot position per window (X/Y/Z; height = Z), relative to each window's
    % start. Window index lines up with the ZVP cycles used everywhere else.
    Seg.zhc.L.posTime = zhcTimeL;   Seg.zhc.L.posGait = zhcGaitL;   % maxLen/NSEG x 3 x nWin
    Seg.zhc.R.posTime = zhcTimeR;   Seg.zhc.R.posGait = zhcGaitR;
    Seg.zhc.L.tCont   = tContL;     Seg.zhc.L.pCont   = pContL;     % whole stitched trajectory
    Seg.zhc.R.tCont   = tContR;     Seg.zhc.R.pCont   = pContR;
    Seg.zhc.L.tZvp    = tZvpL;      Seg.zhc.L.pZvp    = pZvpL;      % ZVP boundary markers
    Seg.zhc.R.tZvp    = tZvpR;      Seg.zhc.R.pZvp    = pZvpR;
end
segFile = fullfile(base, sprintf('SegmentedParams_Test%d.mat', tn));
save(segFile, 'Seg');
fprintf('Saved segmentation struct ''Seg'' to:\n  %s\n', segFile);

%% ===================== FIGURE 2 - STRIDE-NORMALIZED (0-100%%) =====================
defOn = {'IMU: Left Foot (Dot) X', 'IMU: Left Foot (Awinda) X'};
buildViewer(sprintf('Step 4 - stride-normalized  |  Test %d', Data.test), ...
            segT, segY, segL, defOn, FONT_NAME, base, tn, 'Gait cycle (%)', 100, 'StrideNormalized');

%% ===================== FIGURE 3 - STRIDE TIME-DOMAIN (s) =====================
buildViewer(sprintf('Step 4 - stride time-domain  |  Test %d', Data.test), ...
            segTt, segYt, segL, defOn, FONT_NAME, base, tn, 'Time (s)', tvec(end), 'StrideTime');

%% ===================== FIGURE 4 - ZHC HEIGHT PER WINDOW =====================
if zhcOK
    zhcHeightFig(zhcTimeL, zhcTimeR, tvec, FONT_NAME, Data.test);
    zhcWholeFig(tContL, pContL, tZvpL, pZvpL, tContR, pContR, tZvpR, pZvpR, FONT_NAME, Data.test);
end

fprintf('ZVP indices in zvpL / zvpR; normalized curves in segY, time-domain in segYt.\n');
if zhcOK
    fprintf('ZHC per-window in Seg.zhc.L/.R (.posTime, .posGait; height = column 3).\n');
    fprintf('ZHC whole trajectory in Seg.zhc.L/.R (.tCont, .pCont = N x 3 [X Y Z]).\n');
end

%% ========================================================================
%  LOCAL FUNCTIONS
%% ========================================================================
function col = pickAxis(E)
    [~, col] = max(max(E,[],1) - min(E,[],1));
end

function [toeOff, heelStrike, cand, realZ, omegaNorm, accNorm] = ...
        detectGaitEvents(rollAngle, angVel, acc, minProm, minPkDist, omThr, accThr)
    [~, toeOff] = findpeaks(-rollAngle, 'MinPeakProminence', minProm, 'MinPeakDistance', minPkDist);
    heelStrike = [];
    for i = 1:numel(toeOff)-1
        s = toeOff(i); e = toeOff(i+1);
        if e <= s+2, continue; end
        seg = rollAngle(s:e);
        [~, locs] = findpeaks(seg, 'MinPeakProminence', minProm);
        if ~isempty(locs)
            [~, im] = max(seg(locs));
            heelStrike(end+1) = s + locs(im) - 1; %#ok<AGROW>
        end
    end
    omegaNorm = sqrt(sum(angVel.^2, 2));
    accNorm   = sqrt(sum(acc.^2,   2));
    cand = find((omegaNorm < omThr) & (accNorm < accThr));
    realZ = [];
    for i = 1:numel(toeOff)-1
        s = toeOff(i); e = toeOff(i+1);
        if e <= s+2, continue; end
        c = cand(cand >= s & cand <= e);
        if isempty(c), continue; end
        realZ(end+1) = round((c(1) + c(end)) / 2); %#ok<AGROW>
    end
    realZ = realZ(:);
    toeOff = toeOff(:); heelStrike = heelStrike(:);
end

function A = segmentAll(t, y, zvp, Nseg, method)
% Strides between consecutive ZVPs, normalized to Nseg points. Nseg x nStrides.
    nStr = numel(zvp) - 1;
    if nStr < 1, A = nan(Nseg,1); return; end
    A = nan(Nseg, nStr);
    for s = 1:nStr
        a = zvp(s); b = zvp(s+1);
        if b <= a+1, continue; end
        tt = t(a:b); seg = y(a:b);
        ok = ~isnan(seg);
        if nnz(ok) < 2, continue; end
        tq = linspace(tt(1), tt(end), Nseg);
        A(:,s) = interp1(tt(ok), seg(ok), tq, method);
    end
    A(:, all(isnan(A),1)) = [];
    if isempty(A), A = nan(Nseg,1); end
end

function A = segmentAllTime(y, zvp, maxLen)
% Raw (non-normalized) strides between consecutive ZVPs, NaN-padded to maxLen
% rows. Column s = the stride's samples in time (relative to its own start).
    nStr = numel(zvp) - 1;
    if nStr < 1, A = nan(maxLen,1); return; end
    A = nan(maxLen, nStr);
    for s = 1:nStr
        a = zvp(s); b = zvp(s+1);
        if b <= a+1, continue; end
        seg = y(a:b);  nkeep = min(numel(seg), maxLen);
        A(1:nkeep, s) = seg(1:nkeep);
    end
    A(:, all(isnan(A),1)) = [];
    if isempty(A), A = nan(maxLen,1); end
end

function m = strideMax(zvp)   % longest stride length (samples, inclusive)
    if numel(zvp) < 2, m = 1; else, m = max(diff(zvp)) + 1; end
end

function RM = rotationMatrixRef(eulerAngle)
% Verbatim port of RotationMatrix_fcn: R = Rz(yaw)*Ry(pitch)*Rx(roll), angles in
% degrees, eulerAngle = [roll pitch yaw]. Returns 3x3xN.
    N = size(eulerAngle,1);  RM = zeros(3,3,N);
    for i = 1:N
        Rz = [cosd(eulerAngle(i,3)) -sind(eulerAngle(i,3)) 0;
              +sind(eulerAngle(i,3)) cosd(eulerAngle(i,3)) 0;
                    0         0  1];
        Ry = [cosd(eulerAngle(i,2)) 0 +sind(eulerAngle(i,2));
                   0     1     0;
             -sind(eulerAngle(i,2)) 0  cosd(eulerAngle(i,2))];
        Rx = [1    0           0;
              0  cosd(eulerAngle(i,1))  -sind(eulerAngle(i,1));
              0 +sind(eulerAngle(i,1))   cosd(eulerAngle(i,1))];
        RM(:,:,i) = Rz * Ry * Rx;
    end
end

function [posTime, posGait, tCont, pCont, tZvp, pZvp] = zhcRef(acceleration_IMU1, time, realZUPTIndices, RotationMatrix, Nseg, maxLen, gravity)
% Verbatim port of ZHC_Method_Function (level-ground branch): two integrations
% per stride with the DesiredJacobian bias solve; gain_hs = 1, k_hs_selected = 0
% (heel-strike velocity applied at stride start). Position per window, relative
% to that window's start. posTime = maxLen x 3 x nWin (NaN-padded raw samples),
% posGait = Nseg x 3 x nWin (0-100% grid). tCont / pCont = the whole trajectory
% with windows stitched continuously (each window resumes where the last ended).
% tZvp / pZvp = the ZVP (window-boundary) times and positions on that trajectory.
    gain_hs = 1;
    nWin = max(numel(realZUPTIndices)-1, 0);
    posTime = nan(maxLen, 3, max(nWin,1));
    posGait = nan(Nseg,  3, max(nWin,1));
    tCont = [];  pCont = [];  p_start = [0 0 0];
    tZvp = [];   pZvp = [];   lastT = [];  lastP = [];
    for strideNumber = 1:nWin
        startIdx = realZUPTIndices(strideNumber);
        endIdx   = realZUPTIndices(strideNumber + 1);
        strideLength = endIdx - startIdx;
        if strideLength < 2, continue; end
        k_hs_selected = 0;                     % heel strike at time zero
        v = zeros(strideLength+1, 3);  p = zeros(strideLength+1, 3);
        Bv = zeros(3,3);  Bp = zeros(3,3);
        % --- First integration: no bias ---
        for k = 1:strideLength
            idx = startIdx + k - 1;
            delta_t = time(idx+1) - time(idx);
            acc_world = (RotationMatrix(:,:,idx) * acceleration_IMU1(idx,:)')' - [0 0 gravity];
            v(k+1,:) = v(k,:) + acc_world * delta_t;
            p(k+1,:) = p(k,:) + v(k,:) * delta_t + 0.5 * acc_world * delta_t^2;
            Bv = Bv + RotationMatrix(:,:,idx) * delta_t;
            Bp = Bp + Bv * delta_t - 0.5 * RotationMatrix(:,:,idx) * delta_t^2;
        end
        % --- Bias solve (level ground) ---
        idx_hs_global = startIdx + k_hs_selected;
        T_post_hs = time(endIdx) - time(idx_hs_global);
        DesiredJacobian = [Bv(1,:), 0;
                           Bv(2,:), 0;
                           Bv(3,:), 1;
                           Bp(3,:), T_post_hs];
        v_last = v(end,:);
        pz_end_rel = p(end,3) - p(1,3);
        biasVector = pinv(DesiredJacobian) * [v_last, pz_end_rel]';
        biasAcc  = biasVector(1:3);
        biasV_hs = biasVector(4);
        % --- Second integration: with removing bias ---
        v = zeros(strideLength+1, 3);  p = zeros(strideLength+1, 3);
        v(1,:) = v(1,:) - gain_hs * [0 0 biasV_hs];
        for k = 1:strideLength
            idx = startIdx + k - 1;
            delta_t = time(idx+1) - time(idx);
            acc_world = (RotationMatrix(:,:,idx) * (acceleration_IMU1(idx,:)' - biasAcc))' - [0 0 gravity];
            v(k+1,:) = v(k,:) + acc_world * delta_t;
            p(k+1,:) = p(k,:) + v(k,:) * delta_t + 0.5 * acc_world * delta_t^2;
        end
        n = min(strideLength+1, maxLen);
        posTime(1:n,:,strideNumber) = p(1:n,:);              % window-relative (starts at 0)
        tt = time(startIdx:endIdx) - time(startIdx);
        posGait(:,:,strideNumber) = interp1(tt, p, linspace(tt(1), tt(end), Nseg), 'spline');
        % Stitch into the continuous whole trajectory (carry the running start).
        pAbs   = p + p_start;                                % resume where last window ended
        tCont  = [tCont;  time(startIdx:endIdx)];   %#ok<AGROW>
        pCont  = [pCont;  pAbs];                     %#ok<AGROW>
        % ZVP marker at this window's start (boundary); keep the final end too.
        tZvp   = [tZvp; time(startIdx)];   pZvp = [pZvp; pAbs(1,:)];  %#ok<AGROW>
        lastT  = time(endIdx);             lastP = pAbs(end,:);
        p_start = pAbs(end,:);
    end
    if ~isempty(lastT), tZvp = [tZvp; lastT];  pZvp = [pZvp; lastP]; end
end

function zhcHeightFig(ptL, ptR, tvec, fn, testNo)
% ZHC height (Z) per time for every window, Left / Right toggles.
    hF = figure('Color','w','Name',sprintf('Step 4 - ZHC height per window | Test %d', testNo), ...
                'Position',[90 90 1150 700]);
    cbL = uicontrol(hF,'Style','checkbox','Units','normalized','Position',[0.04 0.945 0.10 0.035], ...
        'String','Left','Value',1,'BackgroundColor','w','FontName',fn,'FontWeight','bold', ...
        'ForegroundColor',[0 0.45 0.85],'Callback',@(~,~) updZhcH(hF));
    cbR = uicontrol(hF,'Style','checkbox','Units','normalized','Position',[0.15 0.945 0.10 0.035], ...
        'String','Right','Value',1,'BackgroundColor','w','FontName',fn,'FontWeight','bold', ...
        'ForegroundColor',[0.85 0.10 0.10],'Callback',@(~,~) updZhcH(hF));
    ax = axes(hF,'Position',[0.08 0.10 0.88 0.80]);
    S = struct('ax',ax,'cbL',cbL,'cbR',cbR,'HtL',squeeze(ptL(:,3,:)),'HtR',squeeze(ptR(:,3,:)), ...
               'tvec',tvec,'fn',fn);
    guidata(hF,S);  updZhcH(hF);
end

function updZhcH(hF)
    S = guidata(hF);  ax = S.ax;  cla(ax);  hold(ax,'on');  grid(ax,'on');  box(ax,'on');
    xmax = 0;
    if S.cbL.Value==1
        plot(ax, S.tvec, S.HtL, 'Color', [0.00 0.45 0.85], 'LineWidth', 1.0);
        r = find(any(isfinite(S.HtL),2), 1, 'last');  if ~isempty(r), xmax = max(xmax, S.tvec(r)); end
    end
    if S.cbR.Value==1
        plot(ax, S.tvec, S.HtR, 'Color', [0.85 0.10 0.10], 'LineWidth', 1.0);
        r = find(any(isfinite(S.HtR),2), 1, 'last');  if ~isempty(r), xmax = max(xmax, S.tvec(r)); end
    end
    hold(ax,'off');  ax.FontName = S.fn;  ax.FontWeight = 'bold';  ax.FontSize = 11;
    if xmax > 0, xlim(ax, [0 xmax]); end
    xlabel(ax,'Time (s)','FontSize',14,'FontWeight','bold');
    ylabel(ax,'Height (m)','FontSize',14,'FontWeight','bold');
    title(ax,'ZHC foot height per window (blue = Left, red = Right)','FontWeight','bold','FontSize',14);
end

function zhcWholeFig(tL, pL, tzL, pzL, tR, pR, tzR, pzR, fn, testNo)
% Whole stitched ZHC trajectory (all windows joined), styled after
% plot_Trajectory_results but comparing Left vs Right. Two figures:
%   (a) Pz (height) vs time, with ZVP markers and Left / Right / ZVP toggles;
%   (b) 3D trajectory, with Left/Right toggles.
    cL = [0 0.45 0.85];  cR = [0.85 0.10 0.10];

    % --- (a) Height (Pz) vs time, with ZVP markers ---
    f1 = figure('Color','w','Name',sprintf('Step 4 - Whole ZHC height (Pz) | Test %d', testNo), ...
                'Position',[120 100 1050 640]);
    ax = axes(f1,'Position',[0.08 0.14 0.88 0.80]); hold(ax,'on'); grid(ax,'on'); box(ax,'on');
    plot(ax, tL, pL(:,3), 'Color',cL, 'LineWidth',1.8, 'DisplayName','Left',  'Tag','L');
    plot(ax, tR, pR(:,3), 'Color',cR, 'LineWidth',1.8, 'DisplayName','Right', 'Tag','R');
    plot(ax, tzL, pzL(:,3), 'o', 'MarkerSize',7, 'MarkerFaceColor',cL, ...
         'MarkerEdgeColor','k', 'LineStyle','none', 'DisplayName','ZVP (Left)',  'Tag','ZVP');
    plot(ax, tzR, pzR(:,3), 'o', 'MarkerSize',7, 'MarkerFaceColor',cR, ...
         'MarkerEdgeColor','k', 'LineStyle','none', 'DisplayName','ZVP (Right)', 'Tag','ZVP');
    xlabel(ax,'Time (s)','FontWeight','bold','FontSize',13);
    ylabel(ax,'p_Z  (m)','FontWeight','bold','FontSize',13);
    title(ax,'Whole ZHC foot height (blue = Left, red = Right; circles = ZVP)','FontWeight','bold','FontSize',14);
    set(ax,'FontName',fn,'FontWeight','bold'); legend(ax,'Location','best');
    hold(ax,'off');
    uicontrol(f1,'Style','checkbox','String','Show Left','Value',1,'Position',[20 12 110 24], ...
              'FontName',fn,'Callback',@(s,~) toggleTrajLines(s, f1, 'L'));
    uicontrol(f1,'Style','checkbox','String','Show Right','Value',1,'Position',[140 12 110 24], ...
              'FontName',fn,'Callback',@(s,~) toggleTrajLines(s, f1, 'R'));
    uicontrol(f1,'Style','checkbox','String','Show ZVP','Value',1,'Position',[260 12 110 24], ...
              'FontName',fn,'Callback',@(s,~) toggleTrajLines(s, f1, 'ZVP'));

    % --- (b) 3D trajectory ---
    f2 = figure('Color','w','Name',sprintf('Step 4 - Whole ZHC trajectory (3D) | Test %d', testNo), ...
                'Position',[200 130 820 640]);
    hold on; grid on; box on;
    plot3(pL(:,1), pL(:,2), pL(:,3), 'Color',cL, 'LineWidth',1.8, 'DisplayName','Left',  'Tag','L');
    plot3(pR(:,1), pR(:,2), pR(:,3), 'Color',cR, 'LineWidth',1.8, 'DisplayName','Right', 'Tag','R');
    plot3(pzL(:,1), pzL(:,2), pzL(:,3), 'o', 'MarkerSize',7, 'MarkerFaceColor',cL, ...
         'MarkerEdgeColor','k', 'LineStyle','none', 'DisplayName','ZVP (Left)',  'Tag','ZVP');
    plot3(pzR(:,1), pzR(:,2), pzR(:,3), 'o', 'MarkerSize',7, 'MarkerFaceColor',cR, ...
         'MarkerEdgeColor','k', 'LineStyle','none', 'DisplayName','ZVP (Right)', 'Tag','ZVP');
    xlabel('X (m)','FontWeight','bold'); ylabel('Y (m)','FontWeight','bold'); zlabel('Z (m)','FontWeight','bold');
    title('Whole ZHC 3D trajectory (blue = Left, red = Right; circles = ZVP)','FontWeight','bold');
    set(gca,'FontName',fn,'FontWeight','bold'); legend('Location','best'); axis equal; view(3);
    hold off;
    uicontrol(f2,'Style','checkbox','String','Show Left','Value',1,'Position',[20 12 110 24], ...
              'FontName',fn,'Callback',@(s,~) toggleTrajLines(s, f2, 'L'));
    uicontrol(f2,'Style','checkbox','String','Show Right','Value',1,'Position',[140 12 110 24], ...
              'FontName',fn,'Callback',@(s,~) toggleTrajLines(s, f2, 'R'));
    uicontrol(f2,'Style','checkbox','String','Show ZVP','Value',1,'Position',[260 12 110 24], ...
              'FontName',fn,'Callback',@(s,~) toggleTrajLines(s, f2, 'ZVP'));
end

function toggleTrajLines(src, hFig, tagName)
% Show/hide every line tagged tagName across all axes in the figure.
    vis = 'on'; if src.Value == 0, vis = 'off'; end
    h = findobj(hFig, 'Tag', tagName);
    set(h, 'Visible', vis);
end

function s = imuSide(label)   % Left / Pelvis / Sternum -> L ; Right -> R
    if contains(label,'Right'), s = 'R'; else, s = 'L'; end
end
function s = jointSide(name)
    if endsWith(name,'_r'), s = 'R'; else, s = 'L'; end
end
function s = zvpSideIMU(label)
% Foot-ZVP side used to SEGMENT this IMU. Arm IMUs swing with the CONTRALATERAL
% leg, so they are cut on the OPPOSITE foot's ZVPs (left arm -> right foot ZVP).
    s = imuSide(label);
    if isUpperLimb(label), s = otherSide(s); end
end
function s = zvpSideJoint(name)
% Same contralateral rule for shoulder/elbow joints (arm_* / elbow_*).
    s = jointSide(name);
    if isUpperLimb(name), s = otherSide(s); end
end
function tf = isUpperLimb(s)   % arm IMU label or shoulder/elbow joint name
    s = lower(s);  tf = contains(s,'arm') || contains(s,'elbow');
end
function s = otherSide(s)
    if s == 'R', s = 'L'; else, s = 'R'; end
end
function zvp = sideZVP(side, zvpL, zvpR)
    if side == 'R', zvp = zvpR; else, zvp = zvpL; end
end

function drawSide(ax, t, ang, toeOff, hs, zvp, ttl, cAng, cToe, cHs, cZvp, sd)
    [fn, ts, ls, tk, lw] = sd{:};
    axes(ax); hold(ax,'on'); grid(ax,'on'); box(ax,'on');
    plot(ax, t, ang, '-', 'Color', cAng, 'LineWidth', lw);
    plot(ax, t(toeOff), ang(toeOff), 'v', 'Color', cToe, 'MarkerFaceColor', cToe, 'MarkerSize', 7);
    plot(ax, t(hs),     ang(hs),     '^', 'Color', cHs,  'MarkerFaceColor', cHs,  'MarkerSize', 7);
    scatter(ax, t(zvp), ang(zvp), 60, cZvp, 'filled', 'MarkerEdgeColor','k');
    ax.FontName=fn; ax.FontSize=tk; ax.FontWeight='bold';
    title(ax, ttl, 'FontSize', ts, 'FontName', fn, 'Interpreter','none');
    xlabel(ax, 'Time (s)', 'FontSize', ls, 'FontWeight','bold', 'FontName', fn);
    ylabel(ax, 'Roll angle (deg)', 'FontSize', ls, 'FontWeight','bold', 'FontName', fn);
    legend(ax, {'roll','toe-off','heel strike','ZVP'}, 'Location','best');
end

function drawNorms(ax, t, omega, accN, zvp, omThr, accThr, ttl, cOm, cAcc, cZvp, sd)
    [fn, ts, ls, tk, lw] = sd{:};
    axes(ax); hold(ax,'on'); grid(ax,'on'); box(ax,'on');
    plot(ax, t, omega, '-', 'Color', cOm,  'LineWidth', lw);
    plot(ax, t, accN,  '-', 'Color', cAcc, 'LineWidth', lw);
    yline(ax, omThr,  '--', 'Color', cOm);
    yline(ax, accThr, '--', 'Color', cAcc);
    yl = ylim(ax);
    plot(ax, [t(zvp) t(zvp)]', repmat(yl(:),1,numel(zvp)), ':', 'Color', cZvp);
    ax.FontName=fn; ax.FontSize=tk; ax.FontWeight='bold';
    title(ax, ttl, 'FontSize', ts, 'FontName', fn, 'Interpreter','none');
    xlabel(ax, 'Time (s)', 'FontSize', ls, 'FontWeight','bold', 'FontName', fn);
    ylabel(ax, 'Norm', 'FontSize', ls, 'FontWeight','bold', 'FontName', fn);
    legend(ax, {'|gyro|','|acc|','\omega thr','acc thr','ZVP'}, 'Location','best');
end

function buildViewer(titleStr, T, Y, L, defOn, fontName, figDir, tn, xlab, xmax, pngTag)
% Checkbox-panel viewer of stride curves, with a display-mode selector
% ('All strides' / 'Mean +/- SD'). xlab/xmax set the x-axis (gait % or time s).
    if nargin < 9,  xlab = 'Gait cycle (%)'; end
    if nargin < 10, xmax = 100; end
    if nargin < 11, pngTag = 'StrideNormalized'; end
    n = numel(L);
    if exist('turbo','file'), cmap = turbo(n); else, cmap = hsv(n); end
    hF = figure('Color','w','Name',titleStr,'Position',[90 90 1400 800]);
    ax = axes(hF,'Position',[0.34 0.10 0.63 0.82]);
    LX = 0.015; LW = 0.30;

    uicontrol(hF,'Style','text','Units','normalized','Position',[LX 0.95 0.10 0.03], ...
        'String','Display:','BackgroundColor','w','FontName',fontName,'FontWeight','bold','HorizontalAlignment','left');
    dispItems = {'All strides','Mean +/- SD'};
    dispDD = uicontrol(hF,'Style','popupmenu','Units','normalized','Position',[LX+0.10 0.952 0.19 0.03], ...
        'String',dispItems,'Value',1,'FontName',fontName,'Callback',@(~,~) updateViewer(hF));

    uicontrol(hF,'Style','pushbutton','Units','normalized','Position',[LX 0.905 0.09 0.035], ...
        'String','Select all','FontName',fontName,'Callback',@(~,~) setAll(hF,true));
    uicontrol(hF,'Style','pushbutton','Units','normalized','Position',[LX+0.10 0.905 0.09 0.035], ...
        'String','Clear all','FontName',fontName,'Callback',@(~,~) setAll(hF,false));
    uicontrol(hF,'Style','pushbutton','Units','normalized','Position',[LX+0.20 0.905 0.09 0.035], ...
        'String','Save PNG','FontName',fontName,'Callback',@(~,~) savePNGv(hF));

    pnl = uipanel(hF,'Title','Signals','Units','normalized','Position',[LX 0.03 LW 0.85], ...
        'BackgroundColor','w','FontName',fontName,'FontSize',10,'FontWeight','bold');
    rh = 1/n;  cb = gobjects(n,1);
    for k = 1:n
        cb(k) = uicontrol(pnl,'Style','checkbox','Units','normalized', ...
            'Position',[0.03 1-k*rh 0.95 rh*0.92], 'String',L{k}, ...
            'Value',any(strcmp(L{k},defOn)), 'BackgroundColor','w', ...
            'FontName',fontName,'FontSize',9,'Callback',@(~,~) updateViewer(hF));
    end

    S = struct('ax',ax,'cb',cb,'T',{T},'Y',{Y},'L',{L},'color',cmap,'dispDD',dispDD, ...
               'dispItems',{dispItems},'titleStr',titleStr,'fontName',fontName, ...
               'figDir',figDir,'tn',tn,'n',n,'xlab',xlab,'xmax',xmax,'pngTag',pngTag);
    guidata(hF, S); updateViewer(hF);
end

function updateViewer(hF)
    S = guidata(hF); ax = S.ax;
    meanMode = strcmp(S.dispItems{S.dispDD.Value}, 'Mean +/- SD');
    cla(ax); hold(ax,'on'); legH = []; legN = {};
    for k = 1:S.n
        if S.cb(k).Value ~= 1, continue; end
        x = S.T{k}; Y = S.Y{k}; c = S.color(k,:);
        if meanMode
            m = mean(Y,2,'omitnan'); sdv = std(Y,0,2,'omitnan');
            good = ~isnan(m) & ~isnan(sdv);
            xf = [x(good); flipud(x(good))];
            yf = [m(good)+sdv(good); flipud(m(good)-sdv(good))];
            fill(ax, xf, yf, c, 'FaceAlpha',0.18, 'EdgeColor','none');
            hRep = plot(ax, x, m, '-', 'Color', c, 'LineWidth', 2.4);
        else
            hh = plot(ax, x, Y, '-', 'Color', c, 'LineWidth', 1.1);  % every stride
            hRep = hh(1);
        end
        legH(end+1) = hRep; legN{end+1} = S.L{k}; %#ok<AGROW>
    end
    hold(ax,'off'); grid(ax,'on'); box(ax,'on');
    ax.FontName = S.fontName; ax.FontSize = 12; ax.FontWeight = 'bold';
    xlabel(ax,S.xlab,'FontSize',15,'FontWeight','bold','FontName',S.fontName);
    ylabel(ax,'Angle (deg)','FontSize',15,'FontWeight','bold','FontName',S.fontName);
    title(ax,S.titleStr,'FontSize',17,'FontWeight','bold','FontName',S.fontName,'Interpreter','none');
    xlim(ax,[0 S.xmax]);
    if ~isempty(legH)
        legend(ax, legH, legN, 'Location','eastoutside','Interpreter','none','FontSize',9);
    else
        legend(ax,'off');
    end
end

function setAll(hF, val)
    S = guidata(hF);
    for k = 1:S.n, S.cb(k).Value = val; end
    updateViewer(hF);
end

function savePNGv(hF)
    S = guidata(hF);
    if ~exist(S.figDir,'dir'), mkdir(S.figDir); end
    pngFile = fullfile(S.figDir, sprintf('%s_Test%d.png', S.pngTag, S.tn));
    exportgraphics(hF, pngFile, 'Resolution', 300);
    fprintf('PNG saved: %s\n', pngFile);
end
