clc
close all
addpath(fileparts(mfilename('fullpath')));

%% ========================================================================
%% STEP 6 - Camera trajectories: sync to the IMU grid + interactive viewers
%% ========================================================================
% (Combines the former step 6 "sync" and step 7 "view all synced signals".)
%
% PART A - SYNC. Reads the 3-camera reconstruction (L/R toe & heel + obstacle
% markers) from Data/Camera CV/Test N/ (prefers *_refined.xlsx) and lands it on
% the SAME uniform 60 Hz grid as the synced IMU/joint data (AllData, step 3),
% using the 3x left-leg-raise gesture: find the first raise peak in the camera
% L_toe height and in the IMU Left-Foot Euler-X, shift the camera clock so they
% coincide (single shift; end triplet gives the drift check), then resample onto
% Data.time (both ~60 Hz -> interp onto the grid, NOT a rate change; time_s and
% real dropouts preserved). Saves CameraSynced_TestN.mat/.xlsx + CameraSync PNG.
%
% PART B - VIEW. Opens three interactive viewers on the 60 Hz grid:
%   FIG 1 ANGLES (vs time)  - every IMU Euler angle (Dot+Awinda) + joint angle.
%   FIG 2 TRAJECTORIES (vs time) - camera markers (mm) + the ZHC IMU foot height
%          (step 4), MARKER checkboxes + AXIS selector (default Z), ZVP dots,
%          obstacle toggle.
%   FIG 3 TRAJECTORIES (3D) - the same markers as X/Y/Z paths (rotatable).
%
% Inputs: AllData_TestN.mat (step 3, required), Camera CV workbook (step 6 CV/
% refine), SegmentedParams_TestN.mat (step 4, optional - adds ZHC/ZVP).

%% ===================== SETTINGS =====================
SYNC_MARKER    = 'L_toe';   % camera marker whose height carries the raise gesture
SYNC_FALLBACK  = 'L_heel';  % used if L_toe has too few valid raise peaks
CAM_RAISE_MIN_MM  = 350;    % height that isolates a leg-raise from a walking swing
CAM_RAISE_MIN_SEP = 0.6;    % s, min separation between raise peaks
IMU_SYNC_LABEL    = 'Left Foot (Dot)';  % IMU trace for the first-raise reference
IMU_SYNC_COL      = 2;      % Euler ZXY -> X (roll); 1=Z 2=X 3=Y
IMU_RAISE_MIN_DEG = 45;     % raises reach ~60 deg; walking swings stay below this
IMU_RAISE_MIN_SEP = 0.6;    % s
TRIPLET_SPAN_S = 4.0;       % the 3-raise gesture spans < this (to group a triplet)
MAX_GAP_S      = 0.10;      % don't interpolate the camera across gaps longer than this
MARKERS = {'L_toe','L_heel','R_toe','R_heel','obstacle1','obstacle2'};

% Viewer defaults
DEFAULT_ANGLES  = {'Joint: knee_angle_l (deg)','Joint: hip_flexion_l (deg)','IMU: Left Foot (Dot) X (deg)'};
DEFAULT_MARKERS = {'L_toe','L_heel','ZHC L foot'};    % fig 2 opening selection
DEFAULT_3D      = {'L_toe','L_heel','R_toe','R_heel'};% fig 3 opening selection
IMU_COMPS = {'Z','X','Y'};  % euler_ZXY_deg column order

%% ===================== APPEARANCE =====================
FONT_NAME = 'Arial'; TITLE_SIZE = 14; LABEL_SIZE = 12; LINE_WIDTH = 1.5;
COL_CAM = [0.45 0.20 0.70];  COL_IMU = [0.10 0.40 0.85];
% Fixed colour per marker (traces keep their colour across both viewers).
MK_COLOR = struct('L_toe',[0.45 0.20 0.70], 'L_heel',[0.15 0.55 0.20], ...
                  'R_toe',[0.80 0.15 0.15], 'R_heel',[0.90 0.55 0.10], ...
                  'obstacle1',[0.10 0.45 0.75], 'obstacle2',[0.40 0.40 0.40], ...
                  'ZHC_L_foot',[0 0 0], 'ZHC_R_foot',[0.85 0.10 0.60]);

%% ===================== INPUT + PATHS =====================
% Set TN before running (e.g. `TN = 22;`) to skip the prompt for batch runs.
if exist('TN','var') && ~isempty(TN), tn = TN; else, tn = input('  Input Test Number: '); end
root = fileparts(fileparts(mfilename('fullpath')));      % parent of Analysis
base = fullfile(root, 'Results','Parameters Output', ['Test ' num2str(tn)]);
matFile = fullfile(base, sprintf('AllData_Test%d.mat', tn));
if ~isfile(matFile)
    base2 = fullfile('..','Results','Parameters Output', ['Test ' num2str(tn)]);
    mf2   = fullfile(base2, sprintf('AllData_Test%d.mat', tn));
    if isfile(mf2), base = base2; matFile = mf2; end
end
if ~isfile(matFile), error('Not found: %s  (run step 3 for Test %d first).', matFile, tn); end
load(matFile, 'Data');
tg = Data.time(:);                 % uniform 60 Hz IMU/joint grid (t=0 at IMU sync)
fs = Data.fs;

% --- locate the camera trajectory workbook (prefer *_refined) ---
camDir = fullfile(root, 'Data','Camera CV', ['Test ' num2str(tn)]);
if ~isfolder(camDir), camDir = fullfile('..','Data','Camera CV', ['Test ' num2str(tn)]); end
if ~isfolder(camDir), error('Camera CV folder not found: %s', camDir); end
xf = pickXlsx(camDir, '*refined*.xlsx');
if isempty(xf), xf = pickXlsx(camDir, '*trajectory*.xlsx'); end
if isempty(xf), xf = pickXlsx(camDir, '*.xlsx'); end
if isempty(xf), error('No trajectory .xlsx in %s', camDir); end
xlsFile = fullfile(camDir, xf(1).name);
if contains(lower(xf(1).name),'refined'), tag = '  [refined]'; else, tag = ''; end
fprintf('Camera : %s%s\n', xlsFile, tag);
fprintf('IMU    : %s  (%d samples @ %g Hz, %.1f s)\n', matFile, numel(tg), fs, tg(end));

%% ===================== READ CAMERA MARKERS =====================
T  = readtable(xlsFile, 'Sheet', 'markers', 'VariableNamingRule','preserve');
vn = string(T.Properties.VariableNames);
tCam = T{:, find(startsWith(lower(vn),'time'),1)};  tCam = tCam(:);
camRaw = struct();
for k = 1:numel(MARKERS)
    m = MARKERS{k};
    cx = find(vn == string(m) + "_x_mm", 1);
    cy = find(vn == string(m) + "_y_mm", 1);
    cz = find(vn == string(m) + "_z_mm", 1);
    if isempty(cx) || isempty(cy) || isempty(cz)
        camRaw.(m) = nan(numel(tCam),3);
    else
        camRaw.(m) = [T{:,cx}, T{:,cy}, T{:,cz}];
    end
end

%% ===================== RAISE PEAKS (camera + IMU) =====================
sm = SYNC_MARKER;
[cPt, ~] = raisePeaks(tCam, camRaw.(sm)(:,3), CAM_RAISE_MIN_MM, CAM_RAISE_MIN_SEP);
if numel(cPt) < 3
    sm = SYNC_FALLBACK;
    [cPt, ~] = raisePeaks(tCam, camRaw.(sm)(:,3), CAM_RAISE_MIN_MM, CAM_RAISE_MIN_SEP);
end
if isempty(cPt), error('No camera leg-raise peaks found (marker %s, > %g mm).', sm, CAM_RAISE_MIN_MM); end
[cStartT, cEndT] = tripletEnds(cPt, TRIPLET_SPAN_S);
fprintf('\nCamera raises (%s z): %d peaks; start@ %.3f s, end@ %.3f s\n', sm, numel(cPt), cStartT, cEndT);

iL = find(strcmp({Data.imu.label}, IMU_SYNC_LABEL), 1);
if isempty(iL), error('IMU trace "%s" not found in Data.imu.', IMU_SYNC_LABEL); end
EX = Data.imu(iL).euler_ZXY_deg(:, IMU_SYNC_COL);
EX = EX - mean(EX(1:min(20,end)), 'omitnan');
[pP,vP] = raisePeaks(tg, EX,  IMU_RAISE_MIN_DEG, IMU_RAISE_MIN_SEP);
[pN,vN] = raisePeaks(tg, -EX, IMU_RAISE_MIN_DEG, IMU_RAISE_MIN_SEP);
if mean3(vP) >= mean3(vN), iSign = 1; iPt = pP; else, iSign = -1; iPt = pN; end
EXs = iSign * EX;
if isempty(iPt), error('No IMU leg-raise peaks >= %g deg found in %s.', IMU_RAISE_MIN_DEG, IMU_SYNC_LABEL); end
[iStartT, iEndT] = tripletEnds(iPt, TRIPLET_SPAN_S);
fprintf('IMU raises (%s X, sign %+d): %d peaks; start@ %.3f s, end@ %.3f s\n', ...
        IMU_SYNC_LABEL, iSign, numel(iPt), iStartT, iEndT);

%% ===================== SYNC: single shift + drift check =====================
dtShift = iStartT - cStartT;
drift   = iEndT - (cEndT + dtShift);
tCamAl  = tCam + dtShift;
fprintf('\n=== Sync ===\n  shift (IMU - camera) = %+.3f s\n  end-triplet residual = %+.3f s over %.1f s  (%.3f %%)\n', ...
        dtShift, drift, iEndT - iStartT, 100*drift/max(iEndT-iStartT,eps));

%% ===================== RESAMPLE ONTO Data.time =====================
Cam = struct('test',tn,'fs',fs,'time',tg,'units','mm','sync_marker',sm,'markerNames',{MARKERS});
Cam.markers = struct();
for k = 1:numel(MARKERS)
    Cam.markers.(MARKERS{k}) = resampleToGrid(tCamAl, camRaw.(MARKERS{k}), tg, MAX_GAP_S);
end
Cam.raw  = struct('time', tCam, 'time_aligned', tCamAl, 'markers', camRaw);
Cam.sync = struct('shift_s', dtShift, 'drift_s', drift, 'cam_marker', sm, ...
                  'cam_start_peak_s', cStartT, 'cam_end_peak_s', cEndT, ...
                  'imu_label', IMU_SYNC_LABEL, 'imu_sign', iSign, ...
                  'imu_start_peak_s', iStartT, 'imu_end_peak_s', iEndT, 'max_gap_s', MAX_GAP_S);

%% ===================== SAVE .mat + .xlsx =====================
outMat = fullfile(base, sprintf('CameraSynced_Test%d.mat', tn));
save(outMat, 'Cam');
Tout = table(tg, 'VariableNames', {'time_s'});
for k = 1:numel(MARKERS)
    m = MARKERS{k}; G = Cam.markers.(m);
    Tout.([m '_x_mm']) = G(:,1); Tout.([m '_y_mm']) = G(:,2); Tout.([m '_z_mm']) = G(:,3);
end
outXls = fullfile(base, sprintf('CameraSynced_Test%d.xlsx', tn));
if isfile(outXls), delete(outXls); end
writetable(Tout, outXls, 'Sheet', 'markers_60Hz');
Ssum = table( ["shift_s";"drift_s";"cam_start_peak_s";"cam_end_peak_s";"imu_start_peak_s";"imu_end_peak_s";"imu_sign";"max_gap_s"], ...
              [dtShift; drift; cStartT; cEndT; iStartT; iEndT; iSign; MAX_GAP_S], 'VariableNames', {'field','value'});
writetable(Ssum, outXls, 'Sheet', 'sync');
fprintf('\nSaved %s\n       %s\n', outMat, outXls);

%% ===================== SYNC-CHECK FIGURE (saved PNG) =====================
zc = Cam.raw.markers.(sm)(:,3);
f1 = figure('Color','w','Name',sprintf('Step 6 - camera<->IMU sync | Test %d', tn),'Position',[70 70 1360 820]);
subplot(2,1,1); syncOverlay(tCamAl, zc, cPt+dtShift, tg, EXs, iPt, ...
    sprintf('Full trial - camera %s height (aligned) vs IMU %s X', sm, IMU_SYNC_LABEL), COL_CAM, COL_IMU, LINE_WIDTH, FONT_NAME, LABEL_SIZE);
xlim([tg(1) tg(end)]);
title(sprintf('Test %d  |  shift = %+.3f s,  end-drift = %+.3f s', tn, dtShift, drift), 'FontName',FONT_NAME,'FontSize',TITLE_SIZE,'FontWeight','bold');
subplot(2,2,3); syncOverlay(tCamAl, zc, cPt+dtShift, tg, EXs, iPt, 'Start gesture (zoom)', COL_CAM, COL_IMU, LINE_WIDTH, FONT_NAME, LABEL_SIZE);
xlim([iStartT-2.5, iStartT+6]);
subplot(2,2,4); syncOverlay(tCamAl, zc, cPt+dtShift, tg, EXs, iPt, 'End gesture (zoom)', COL_CAM, COL_IMU, LINE_WIDTH, FONT_NAME, LABEL_SIZE);
xlim([iEndT-2.5, iEndT+6]);
png1 = fullfile(base, sprintf('CameraSync_Test%d.png', tn));
exportgraphics(f1, png1, 'Resolution', 200);
fprintf('Saved %s\n', png1);

%% ===================== PART B: LOAD Seg (ZHC/ZVP) + BUILD VIEWER DATA =====================
segFile = fullfile(base, sprintf('SegmentedParams_Test%d.mat', tn));
haveSeg = isfile(segFile);
if haveSeg, load(segFile, 'Seg'); else, warning('No %s - ZHC/ZVP omitted in the trajectory viewer (run step 4).', segFile); end
t = tg;

% --- ANGLES list (deg): IMU Euler + joints ---
Ta={}; Ya={}; La={};
for i = 1:numel(Data.imu)
    E = Data.imu(i).euler_ZXY_deg;
    for a = 1:3
        Ta{end+1}=t; Ya{end+1}=E(:,a); La{end+1}=sprintf('IMU: %s %s (deg)', Data.imu(i).label, IMU_COMPS{a}); %#ok<SAGROW>
    end
end
if isfield(Data,'joints') && ~isempty(Data.joints.angles_deg)
    for j = 1:numel(Data.joints.labels)
        Ta{end+1}=t; Ya{end+1}=Data.joints.angles_deg(:,j); La{end+1}=sprintf('Joint: %s (deg)', Data.joints.labels{j}); %#ok<SAGROW>
    end
end

% --- TRAJECTORY structs (mm): feet + ZHC in traj (tagged L/R); obstacles in obst ---
traj = struct('name',{},'color',{},'side',{},'t',{},'XYZ',{},'zvpT',{},'zvpXYZ',{});
obst = struct('name',{},'color',{},'t',{},'XYZ',{});
for k = 1:numel(Cam.markerNames)
    m = Cam.markerNames{k}; G = Cam.markers.(m);
    if ~any(isfinite(G(:))), continue; end
    if startsWith(m,'obstacle')
        obst(end+1) = struct('name',m,'color',mkColor(MK_COLOR,m),'t',t,'XYZ',G); %#ok<SAGROW>
    else
        sd = 'L'; if startsWith(m,'R'), sd = 'R'; end
        traj(end+1) = struct('name',m,'color',mkColor(MK_COLOR,m),'side',sd,'t',t,'XYZ',G,'zvpT',[],'zvpXYZ',[]); %#ok<SAGROW>
    end
end
if haveSeg && isfield(Seg,'zhc')
    for side = {'L','R'}
        s = Seg.zhc.(side{1}); nm = sprintf('ZHC %s foot', side{1});
        traj(end+1) = struct('name',nm,'color',mkColor(MK_COLOR,strrep(nm,' ','_')),'side',side{1}, ...
            't',s.tCont(:),'XYZ',s.pCont*1000,'zvpT',s.tZvp(:),'zvpXYZ',s.pZvp*1000); %#ok<SAGROW>
    end
end
% Gait-event times per side (toe-off / heel-strike), from step4's Seg (if present).
ev = struct('L',struct('toe',[],'hs',[],'zvp',[],'ang',[]), 'R',struct('toe',[],'hs',[],'zvp',[],'ang',[]));
if haveSeg
    if isfield(Seg,'toeL'), ev.L.toe = idx2t(tg, Seg.toeL); end
    if isfield(Seg,'hsL'),  ev.L.hs  = idx2t(tg, Seg.hsL);  end
    if isfield(Seg,'toeR'), ev.R.toe = idx2t(tg, Seg.toeR); end
    if isfield(Seg,'hsR'),  ev.R.hs  = idx2t(tg, Seg.hsR);  end
    if isfield(Seg,'zvpL'), ev.L.zvp = idx2t(tg, Seg.zvpL); end
    if isfield(Seg,'zvpR'), ev.R.zvp = idx2t(tg, Seg.zvpR); end
end
% Foot roll angle per side (the Dot-foot Euler-X signal the events were detected
% from) - for the sanity overlay in the vs-time viewer (right y-axis).
ev.tg = tg;
iLd = find(strcmp({Data.imu.label},'Left Foot (Dot)'),1);
iRd = find(strcmp({Data.imu.label},'Right Foot (Dot)'),1);
if ~isempty(iLd), ev.L.ang = Data.imu(iLd).euler_ZXY_deg(:,2); end
if ~isempty(iRd), ev.R.ang = Data.imu(iRd).euler_ZXY_deg(:,2); end

%% ===================== OPEN THE VIEWERS =====================
buildAnglesViewer(sprintf('Angles: IMU Euler + joints  |  Test %d', tn), Ta, Ya, La, DEFAULT_ANGLES, FONT_NAME);
buildTrajTimeViewer(sprintf('Trajectories vs time (o=ZVP, v=toe-off, s=heel-strike)  |  Test %d', tn), traj, obst, ev, DEFAULT_MARKERS, FONT_NAME);
buildTraj3DViewer(sprintf('Trajectories 3D (X/Y/Z)  |  Test %d', tn), traj, obst, ev, DEFAULT_3D, FONT_NAME);
fprintf('\nDone. Camera synced to Data.time; viewers open: angles (fig1), trajectories vs time (fig2), 3D (fig3).\n');

%% ========================================================================
%  LOCAL FUNCTIONS - SYNC
%% ========================================================================
function xf = pickXlsx(camDir, pattern)
% Files matching pattern, excluding Excel lock files (~$...), newest first.
    xf = dir(fullfile(camDir, pattern));
    if ~isempty(xf), xf = xf(~startsWith({xf.name}, '~$')); end
    if numel(xf) > 1, [~,ord] = sort([xf.datenum],'descend'); xf = xf(ord); end
end

function [pt, pv] = raisePeaks(t, y, minH, minSepS)
% Local maxima above minH, greedily thinned to >= minSepS apart (tallest kept).
    ok = isfinite(t) & isfinite(y);  t = t(ok); y = y(ok);
    pt = []; pv = [];
    if numel(y) < 3, return; end
    isMax = [false; y(2:end-1) > y(1:end-2) & y(2:end-1) >= y(3:end); false];
    cand  = find(isMax & y >= minH);
    if isempty(cand), return; end
    [~, ord] = sort(y(cand), 'descend');
    keep = false(numel(cand),1); kt = [];
    for j = ord(:)'
        c = cand(j);
        if isempty(kt) || all(abs(t(c) - kt) >= minSepS), keep(j) = true; kt(end+1) = t(c); end %#ok<AGROW>
    end
    sel = sort(cand(keep));  pt = t(sel); pv = y(sel);
end

function [startT, endT] = tripletEnds(pt, spanS)
    startT = pt(1);
    endGrp = pt(pt >= pt(end) - spanS);  endT = endGrp(1);
end

function m = mean3(v)
    if isempty(v), m = 0; else, m = mean(v(1:min(3,end))); end
end

function G = resampleToGrid(tsrc, V, tg, maxGap)
% Linear-interpolate each column of V onto tg; blank grid points farther than
% maxGap from any real sample so genuine dropouts stay as gaps.
    G = nan(numel(tg), size(V,2));
    for c = 1:size(V,2)
        ok = isfinite(tsrc) & isfinite(V(:,c));
        if nnz(ok) < 2, continue; end
        ts = tsrc(ok); vs = V(ok,c);
        [ts, ui] = unique(ts, 'stable'); vs = vs(ui);
        [ts, so] = sort(ts); vs = vs(so);
        gi  = interp1(ts, vs, tg, 'linear', NaN);
        idx = interp1(ts, (1:numel(ts))', tg, 'nearest', 'extrap');
        gi(abs(tg - ts(idx)) > maxGap) = NaN;
        G(:,c) = gi;
    end
end

function syncOverlay(tc, zc, cPk, ti, xi, iPk, ttl, colC, colI, lw, fn, ls)
% Twin-axis overlay: camera height (left) + IMU angle (right), peaks marked.
    yyaxis left
    plot(tc, zc, '-', 'Color', colC, 'LineWidth', lw); hold on;
    plot(cPk, interp1(tc(isfinite(zc)), zc(isfinite(zc)), cPk, 'nearest','extrap'), 'v', 'Color', colC, 'MarkerFaceColor', colC, 'MarkerSize', 7);
    ylabel('Camera height z (mm)','FontWeight','bold','FontSize',ls);  ax = gca; ax.YColor = colC;
    yyaxis right
    plot(ti, xi, '-', 'Color', colI, 'LineWidth', lw);
    plot(iPk, interp1(ti, xi, iPk, 'nearest','extrap'), '^', 'Color', colI, 'MarkerFaceColor', colI, 'MarkerSize', 7);
    ylabel('IMU foot angle (deg)','FontWeight','bold','FontSize',ls);  ax = gca; ax.YColor = colI; ax.FontName = fn;
    grid on; box on;
    xlabel('Time (s)  [IMU sync frame]','FontWeight','bold','FontSize',ls);
    title(ttl, 'FontName', fn, 'FontWeight','bold','Interpreter','tex');
end

%% ========================================================================
%  LOCAL FUNCTIONS - VIEWERS
%% ========================================================================
function c = mkColor(map, name)
    if isfield(map, name), c = map.(name); else, c = [0.2 0.2 0.2]; end
end
function s = onoff(b)
    if b, s = 'on'; else, s = 'off'; end
end
function te = idx2t(tg, idx)
% Sample indices -> times on the grid tg (drop any out-of-range index).
    idx = idx(:); idx = idx(idx >= 1 & idx <= numel(tg)); te = tg(idx);
end
function markEvents(ax, tt, yv, te, mk, c)
% Mark event times te on a time-series trace: sample the trace value at the
% nearest sample within 50 ms; skip events that fall in a gap.
    if isempty(te), return; end
    good = isfinite(tt) & isfinite(yv);
    if nnz(good) < 2, return; end
    tgood = tt(good); ygood = yv(good);
    [tgood, iu] = unique(tgood);  ygood = ygood(iu);      % interp1 needs unique/sorted x
    if numel(tgood) < 2, return; end
    ii = interp1(tgood, (1:numel(tgood))', te, 'nearest', 'extrap');
    sel = abs(te - tgood(ii)) <= 0.05;
    if ~any(sel), return; end
    scatter(ax, te(sel), ygood(ii(sel)), 34, c, mk, 'filled', 'MarkerEdgeColor','k','LineWidth',0.5);
end
function markEvents3D(ax, tt, P, te, mk, c)
% Mark event times te on a 3D path: sample the XYZ at the nearest sample within 50 ms.
    if isempty(te), return; end
    good = isfinite(tt) & all(isfinite(P),2);
    if nnz(good) < 2, return; end
    tgood = tt(good); Pg = P(good,:);
    [tgood, iu] = unique(tgood);  Pg = Pg(iu,:);          % interp1 needs unique/sorted x
    if numel(tgood) < 2, return; end
    ii = interp1(tgood, (1:numel(tgood))', te, 'nearest', 'extrap');
    sel = abs(te - tgood(ii)) <= 0.05;
    if ~any(sel), return; end
    Q = Pg(ii(sel),:);
    plot3(ax, Q(:,1),Q(:,2),Q(:,3), mk, 'Color',c,'MarkerFaceColor',c,'MarkerEdgeColor','k','MarkerSize',6);
end

%% ----- FIG 1: angles (listbox overlay) -----
function buildAnglesViewer(titleStr, T, Y, L, defOn, fontName)
    n = numel(L);
    if exist('turbo','file'), cmap = turbo(n); else, cmap = hsv(n); end
    hF = figure('Color','w','Name',titleStr,'Position',[60 90 1440 800]);
    ax = axes(hF,'Position',[0.36 0.10 0.60 0.82]);
    LX = 0.012; PW = 0.30;
    uicontrol(hF,'Style','text','Units','normalized','Position',[LX 0.955 0.09 0.03], ...
        'String','Plot style:','BackgroundColor','w','FontName',fontName,'FontWeight','bold','HorizontalAlignment','left');
    sItems = {'Line','Scatter','Both'};
    sDD = uicontrol(hF,'Style','popupmenu','Units','normalized','Position',[LX+0.08 0.957 0.11 0.03], ...
        'String',sItems,'Value',1,'FontName',fontName,'Callback',@(~,~) updAngles(hF));
    uicontrol(hF,'Style','pushbutton','Units','normalized','Position',[LX 0.915 0.10 0.032], ...
        'String','Clear all','FontName',fontName,'Callback',@(~,~) clrAngles(hF));
    uicontrol(hF,'Style','text','Units','normalized','Position',[LX 0.878 PW 0.03], ...
        'String','Select traces (Ctrl/Shift-click):','BackgroundColor','w','FontName',fontName,'HorizontalAlignment','left');
    defIdx = find(ismember(L, defOn)); if isempty(defIdx), defIdx = 1; end
    lb = uicontrol(hF,'Style','listbox','Units','normalized','Position',[LX 0.03 PW 0.845], ...
        'String',L,'Min',0,'Max',n,'Value',defIdx,'FontName',fontName,'FontSize',10,'Callback',@(~,~) updAngles(hF));
    S = struct('ax',ax,'lb',lb,'T',{T},'Y',{Y},'L',{L},'color',cmap,'sDD',sDD,'sItems',{sItems},'titleStr',titleStr,'fontName',fontName);
    guidata(hF, S); updAngles(hF);
end
function updAngles(hF)
    S = guidata(hF); idx = get(S.lb,'Value'); ax = S.ax;
    style = S.sItems{S.sDD.Value};
    useLine = any(strcmp(style,{'Line','Both'})); useScat = any(strcmp(style,{'Scatter','Both'}));
    cla(ax); hold(ax,'on'); legH = []; legN = {};
    for k = idx(:)'
        c = S.color(k,:); h = [];
        if useLine, h = plot(ax, S.T{k}, S.Y{k}, '-', 'Color', c, 'LineWidth', 1.6); end
        if useScat, hs = scatter(ax, S.T{k}, S.Y{k}, 12, c, 'filled'); if isempty(h), h = hs; end; end
        if isempty(h), continue; end
        legH(end+1) = h; legN{end+1} = S.L{k}; %#ok<AGROW>
    end
    hold(ax,'off'); grid(ax,'on'); box(ax,'on'); ax.FontName = S.fontName; ax.FontSize = 12;
    xlabel(ax,'Time (s)  [IMU sync frame]','FontSize',14,'FontWeight','bold');
    ylabel(ax,'Angle (deg)','FontSize',14,'FontWeight','bold');
    title(ax,S.titleStr,'FontSize',15,'FontWeight','bold','FontName',S.fontName,'Interpreter','none');
    if ~isempty(legH), legend(ax, legH, legN, 'Location','eastoutside','Interpreter','none','FontSize',9); else, legend(ax,'off'); end
end
function clrAngles(hF), S = guidata(hF); set(S.lb,'Value',[]); updAngles(hF); end

%% ----- FIG 2: trajectories vs time (marker checkboxes + axis selector) -----
function buildTrajTimeViewer(titleStr, traj, obst, ev, defMk, fontName)
    nM = numel(traj);
    hF = figure('Color','w','Name',titleStr,'Position',[80 70 1440 800]);
    ax = axes(hF,'Position',[0.255 0.10 0.70 0.82]);
    LX = 0.012; PW = 0.205; axNames = {'X','Y','Z'};
    uicontrol(hF,'Style','text','Units','normalized','Position',[LX 0.955 0.05 0.03], ...
        'String','Axis:','BackgroundColor','w','FontName',fontName,'FontWeight','bold','HorizontalAlignment','left');
    axCb = gobjects(3,1);
    for a = 1:3
        axCb(a) = uicontrol(hF,'Style','checkbox','Units','normalized', ...
            'Position',[LX+0.045+(a-1)*0.045, 0.955, 0.045, 0.03],'String',axNames{a}, ...
            'Value',double(a==3),'BackgroundColor','w','FontName',fontName,'FontWeight','bold','Callback',@(~,~) updTrajTV(hF));
    end
    sItems = {'Line','Scatter','Both'};
    sDD = uicontrol(hF,'Style','popupmenu','Units','normalized','Position',[LX 0.912 0.10 0.03], ...
        'String',sItems,'Value',1,'FontName',fontName,'Callback',@(~,~) updTrajTV(hF));
    zvpCb = uicontrol(hF,'Style','checkbox','Units','normalized','Position',[LX+0.11 0.912 0.09 0.03], ...
        'String','ZVP dots','Value',1,'BackgroundColor','w','FontName',fontName,'Callback',@(~,~) updTrajTV(hF));
    toCb = uicontrol(hF,'Style','checkbox','Units','normalized','Position',[LX 0.879 0.10 0.03], ...
        'String','Toe-off (v)','Value',1,'BackgroundColor','w','FontName',fontName,'Callback',@(~,~) updTrajTV(hF));
    hsCb = uicontrol(hF,'Style','checkbox','Units','normalized','Position',[LX+0.105 0.879 0.12 0.03], ...
        'String','Heel-strike (s)','Value',1,'BackgroundColor','w','FontName',fontName,'Callback',@(~,~) updTrajTV(hF));
    footCb = uicontrol(hF,'Style','checkbox','Units','normalized','Position',[LX 0.846 0.145 0.03], ...
        'String','Foot angle (right y)','Value',0,'BackgroundColor','w','FontName',fontName,'Callback',@(~,~) updTrajTV(hF));
    obstCb = uicontrol(hF,'Style','checkbox','Units','normalized','Position',[LX+0.15 0.846 0.09 0.03], ...
        'String','Obstacle','Value',0,'Enable',onoff(~isempty(obst)),'BackgroundColor','w','FontName',fontName,'Callback',@(~,~) updTrajTV(hF));
    uicontrol(hF,'Style','pushbutton','Units','normalized','Position',[LX 0.812 0.10 0.03], ...
        'String','Select all','FontName',fontName,'Callback',@(~,~) setAllTV(hF,true));
    uicontrol(hF,'Style','pushbutton','Units','normalized','Position',[LX+0.105 0.812 0.10 0.03], ...
        'String','Clear all','FontName',fontName,'Callback',@(~,~) setAllTV(hF,false));
    pnl = uipanel(hF,'Title','Markers','Units','normalized','Position',[LX 0.03 PW 0.77], ...
        'BackgroundColor','w','FontName',fontName,'FontSize',11,'FontWeight','bold');
    rh = 1/max(nM,1); cb = gobjects(nM,1);
    for k = 1:nM
        cb(k) = uicontrol(pnl,'Style','checkbox','Units','normalized','Position',[0.06 1-k*rh 0.9 rh*0.9], ...
            'String',traj(k).name,'Value',double(any(strcmp(traj(k).name,defMk))), ...
            'ForegroundColor',traj(k).color,'BackgroundColor','w','FontName',fontName,'FontSize',11,'FontWeight','bold','Callback',@(~,~) updTrajTV(hF));
    end
    S = struct('ax',ax,'cb',cb,'axCb',axCb,'sDD',sDD,'sItems',{sItems},'zvpCb',zvpCb,'toCb',toCb,'hsCb',hsCb,'footCb',footCb,'obstCb',obstCb, ...
               'traj',traj,'obst',obst,'ev',ev,'nM',nM,'axNames',{axNames},'titleStr',titleStr,'fontName',fontName);
    guidata(hF, S); updTrajTV(hF);
end
function updTrajTV(hF)
    S = guidata(hF); ax = S.ax;
    style = S.sItems{S.sDD.Value};
    useLine = any(strcmp(style,{'Line','Both'})); useScat = any(strcmp(style,{'Scatter','Both'}));
    showZVP = S.zvpCb.Value == 1;  useAngle = S.footCb.Value == 1;
    selA = find(arrayfun(@(h) h.Value==1, S.axCb));  multiA = numel(selA) > 1;
    lineSty = {'-','--',':'}; scMk = {'o','s','^'};
    % --- LEFT axis: the trajectories (mm) ---
    yyaxis(ax,'left'); cla(ax); hold(ax,'on'); ax.YAxis(1).Color = [0 0 0];
    legH = []; legN = {}; sidesSel = {};
    xr = [inf -inf]; yr = [inf -inf];   % data extent of the selected traces (for auto-fit)
    for k = 1:S.nM
        if S.cb(k).Value ~= 1, continue; end
        T = S.traj(k); c = T.color; sidesSel{end+1} = T.side; %#ok<AGROW>
        for a = selA(:)'
            y = T.XYZ(:,a); h = [];
            gd = isfinite(T.t) & isfinite(y);
            if any(gd), xr = [min(xr(1),min(T.t(gd))), max(xr(2),max(T.t(gd)))]; yr = [min(yr(1),min(y(gd))), max(yr(2),max(y(gd)))]; end
            if useLine, ls = '-'; if multiA, ls = lineSty{a}; end; h = plot(ax, T.t, y, ls, 'Color', c, 'LineWidth', 1.6); end
            if useScat, hs = scatter(ax, T.t, y, 12, c, scMk{a}, 'filled'); if isempty(h), h = hs; end; end
            if isfield(S.ev, T.side)
                E = S.ev.(T.side);
                if showZVP,          markEvents(ax, T.t, y, E.zvp, 'o', c); end   % ZVP (circle)
                if S.toCb.Value == 1, markEvents(ax, T.t, y, E.toe, 'v', c); end  % toe-off (down triangle)
                if S.hsCb.Value == 1, markEvents(ax, T.t, y, E.hs,  's', c); end  % heel-strike (square)
            end
            if isempty(h), continue; end
            legH(end+1) = h; %#ok<AGROW>
            if multiA, legN{end+1} = sprintf('%s %s', T.name, S.axNames{a}); else, legN{end+1} = T.name; end %#ok<AGROW>
        end
    end
    % --- auto-fit the left axis to the selected data (best zoom on each change) ---
    if isfinite(xr(1)) && xr(2) > xr(1), xlim(ax, xr + 0.02*(xr(2)-xr(1))*[-1 1]); end
    if isfinite(yr(1)) && yr(2) > yr(1), ylim(ax, yr + 0.06*(yr(2)-yr(1))*[-1 1]); end
    if S.obstCb.Value == 1 && ~isempty(S.obst)
        xl = xlim(ax);
        for o = 1:numel(S.obst)
            O = S.obst(o);
            for a = selA(:)'
                med = median(O.XYZ(:,a),'omitnan');
                if ~isfinite(med), continue; end
                ho = plot(ax, xl, [med med], '--', 'Color', O.color, 'LineWidth', 1.4);
                scatter(ax, O.t, O.XYZ(:,a), 14, O.color, 'x', 'LineWidth', 1.0);
                legH(end+1) = ho; %#ok<AGROW>
                if multiA, legN{end+1} = sprintf('%s %s', O.name, S.axNames{a}); else, legN{end+1} = O.name; end %#ok<AGROW>
            end
        end
    end
    grid(ax,'on'); box(ax,'on'); ax.FontName = S.fontName; ax.FontSize = 12;
    xlabel(ax,'Time (s)  [IMU sync frame]','FontSize',14,'FontWeight','bold');
    ylabel(ax, trajYLabel(selA, S.axNames), 'FontSize',14,'FontWeight','bold');
    % --- RIGHT axis: foot roll angle (the event source), sanity overlay ---
    yyaxis(ax,'right'); cla(ax);
    if useAngle && isfield(S.ev,'tg')
        hold(ax,'on'); angC = struct('L',[0 0 0.55],'R',[0.55 0 0]);
        uS = unique(sidesSel);
        for is = 1:numel(uS)
            sd = uS{is}; if ~isfield(S.ev,sd), continue; end; A = S.ev.(sd);
            if ~isfield(A,'ang') || isempty(A.ang), continue; end
            ac = angC.(sd);
            hA = plot(ax, S.ev.tg, A.ang, '-', 'Color', ac, 'LineWidth', 1.0);
            if showZVP,          markEvents(ax, S.ev.tg, A.ang, A.zvp, 'o', ac); end
            if S.toCb.Value == 1, markEvents(ax, S.ev.tg, A.ang, A.toe, 'v', ac); end
            if S.hsCb.Value == 1, markEvents(ax, S.ev.tg, A.ang, A.hs,  's', ac); end
            legH(end+1) = hA; legN{end+1} = sprintf('%s foot roll angle', sd); %#ok<AGROW>
        end
        ylabel(ax,'Foot roll angle (deg)','FontSize',14,'FontWeight','bold'); ax.YAxis(2).Visible = 'on';
    else
        ylabel(ax,''); ax.YAxis(2).Visible = 'off';
    end
    yyaxis(ax,'left');
    % legend key for the event markers (black proxies; shapes only)
    if showZVP,        legH(end+1) = plot(ax,nan,nan,'o','MarkerFaceColor','k','MarkerEdgeColor','k','MarkerSize',6,'LineStyle','none'); legN{end+1} = 'ZVP'; end %#ok<AGROW>
    if S.toCb.Value==1,legH(end+1) = plot(ax,nan,nan,'v','MarkerFaceColor','k','MarkerEdgeColor','k','MarkerSize',7,'LineStyle','none'); legN{end+1} = 'Toe-off'; end %#ok<AGROW>
    if S.hsCb.Value==1,legH(end+1) = plot(ax,nan,nan,'s','MarkerFaceColor','k','MarkerEdgeColor','k','MarkerSize',7,'LineStyle','none'); legN{end+1} = 'Heel-strike'; end %#ok<AGROW>
    title(ax,S.titleStr,'FontSize',15,'FontWeight','bold','FontName',S.fontName,'Interpreter','none');
    if ~isempty(legH), legend(ax, legH, legN, 'Location','eastoutside','Interpreter','none','FontSize',9); else, legend(ax,'off'); end
end
function s = trajYLabel(selA, axNames)
    desc = {'Lateral X (mm)','Walking Y (mm)','Height Z (mm)'};
    if numel(selA)==1, s = desc{selA}; else, s = 'Position (mm)'; end
    if isempty(selA), s = 'Position (mm)'; end
end
function setAllTV(hF, val), S = guidata(hF); for k=1:S.nM, S.cb(k).Value = val; end, updTrajTV(hF); end

%% ----- FIG 3: trajectories 3D (marker checkboxes) -----
function buildTraj3DViewer(titleStr, traj, obst, ev, defMk, fontName)
    nM = numel(traj);
    hF = figure('Color','w','Name',titleStr,'Position',[100 60 1320 800]);
    ax = axes(hF,'Position',[0.26 0.09 0.66 0.84]); hold(ax,'on'); grid(ax,'on'); box(ax,'on');
    LX = 0.012; PW = 0.205;
    zvpCb = uicontrol(hF,'Style','checkbox','Units','normalized','Position',[LX 0.912 0.10 0.03], ...
        'String','ZVP dots','Value',1,'BackgroundColor','w','FontName',fontName,'Callback',@(~,~) updTraj3D(hF));
    toCb = uicontrol(hF,'Style','checkbox','Units','normalized','Position',[LX+0.105 0.912 0.11 0.03], ...
        'String','Toe-off (v)','Value',1,'BackgroundColor','w','FontName',fontName,'Callback',@(~,~) updTraj3D(hF));
    hsCb = uicontrol(hF,'Style','checkbox','Units','normalized','Position',[LX 0.879 0.10 0.03], ...
        'String','Heel-strike (s)','Value',1,'BackgroundColor','w','FontName',fontName,'Callback',@(~,~) updTraj3D(hF));
    obstCb = uicontrol(hF,'Style','checkbox','Units','normalized','Position',[LX+0.105 0.879 0.11 0.03], ...
        'String','Obstacle','Value',0,'Enable',onoff(~isempty(obst)),'BackgroundColor','w','FontName',fontName,'Callback',@(~,~) updTraj3D(hF));
    uicontrol(hF,'Style','pushbutton','Units','normalized','Position',[LX 0.842 0.10 0.03], ...
        'String','Select all','FontName',fontName,'Callback',@(~,~) setAll3D(hF,true));
    uicontrol(hF,'Style','pushbutton','Units','normalized','Position',[LX+0.105 0.842 0.10 0.03], ...
        'String','Clear all','FontName',fontName,'Callback',@(~,~) setAll3D(hF,false));
    pnl = uipanel(hF,'Title','Markers','Units','normalized','Position',[LX 0.03 PW 0.80], ...
        'BackgroundColor','w','FontName',fontName,'FontSize',11,'FontWeight','bold');
    rh = 1/max(nM,1); cb = gobjects(nM,1);
    for k = 1:nM
        cb(k) = uicontrol(pnl,'Style','checkbox','Units','normalized','Position',[0.06 1-k*rh 0.9 rh*0.9], ...
            'String',traj(k).name,'Value',double(any(strcmp(traj(k).name,defMk))), ...
            'ForegroundColor',traj(k).color,'BackgroundColor','w','FontName',fontName,'FontSize',11,'FontWeight','bold','Callback',@(~,~) updTraj3D(hF));
    end
    S = struct('ax',ax,'cb',cb,'zvpCb',zvpCb,'toCb',toCb,'hsCb',hsCb,'obstCb',obstCb,'traj',traj,'obst',obst,'ev',ev,'nM',nM,'titleStr',titleStr,'fontName',fontName);
    guidata(hF, S); updTraj3D(hF); view(ax,3); rotate3d(hF,'on');
end
function updTraj3D(hF)
    S = guidata(hF); ax = S.ax; showZVP = S.zvpCb.Value == 1;
    cla(ax); hold(ax,'on'); legH = []; legN = {};
    for k = 1:S.nM
        if S.cb(k).Value ~= 1, continue; end
        T = S.traj(k); c = T.color; P = T.XYZ;
        h = plot3(ax, P(:,1), P(:,2), P(:,3), '-', 'Color', c, 'LineWidth', 1.4);
        ok = find(all(isfinite(P),2));
        if ~isempty(ok)
            plot3(ax, P(ok(1),1),P(ok(1),2),P(ok(1),3),'o','Color',c,'MarkerFaceColor',c,'MarkerSize',7);
            plot3(ax, P(ok(end),1),P(ok(end),2),P(ok(end),3),'s','Color',c,'MarkerFaceColor','w','MarkerSize',9,'LineWidth',1.3);
        end
        if isfield(S.ev, T.side)
            E = S.ev.(T.side);
            if showZVP,          markEvents3D(ax, T.t, P, E.zvp, 'o', c); end   % ZVP
            if S.toCb.Value == 1, markEvents3D(ax, T.t, P, E.toe, 'v', c); end   % toe-off
            if S.hsCb.Value == 1, markEvents3D(ax, T.t, P, E.hs,  's', c); end   % heel-strike
        end
        legH(end+1) = h; legN{end+1} = T.name; %#ok<AGROW>
    end
    if S.obstCb.Value == 1 && ~isempty(S.obst)
        for o = 1:numel(S.obst)
            O = S.obst(o); c = O.color; P = O.XYZ;
            hd = plot3(ax, P(:,1),P(:,2),P(:,3),'x','Color',c,'MarkerSize',6,'LineWidth',1.0);
            med = median(P,1,'omitnan');
            if all(isfinite(med)), plot3(ax, med(1),med(2),med(3),'d','Color',c,'MarkerFaceColor',c,'MarkerSize',11,'MarkerEdgeColor','k'); end
            legH(end+1) = hd; legN{end+1} = O.name; %#ok<AGROW>
        end
    end
    % legend key for the event markers (black proxies; shapes only)
    if S.zvpCb.Value==1, legH(end+1) = plot3(ax,nan,nan,nan,'o','MarkerFaceColor','k','MarkerEdgeColor','k','MarkerSize',6,'LineStyle','none'); legN{end+1} = 'ZVP'; end %#ok<AGROW>
    if S.toCb.Value==1,  legH(end+1) = plot3(ax,nan,nan,nan,'v','MarkerFaceColor','k','MarkerEdgeColor','k','MarkerSize',6,'LineStyle','none'); legN{end+1} = 'Toe-off'; end %#ok<AGROW>
    if S.hsCb.Value==1,  legH(end+1) = plot3(ax,nan,nan,nan,'s','MarkerFaceColor','k','MarkerEdgeColor','k','MarkerSize',6,'LineStyle','none'); legN{end+1} = 'Heel-strike'; end %#ok<AGROW>
    ax.XLimMode='auto'; ax.YLimMode='auto'; ax.ZLimMode='auto';   % auto-fit to selection
    grid(ax,'on'); box(ax,'on'); axis(ax,'equal'); ax.FontName = S.fontName; ax.FontSize = 11;
    xlabel(ax,'X - lateral (mm)','FontWeight','bold'); ylabel(ax,'Y - walking (mm)','FontWeight','bold'); zlabel(ax,'Z - height (mm)','FontWeight','bold');
    title(ax,[S.titleStr '   (o = start, square = end)'],'FontSize',14,'FontWeight','bold','FontName',S.fontName,'Interpreter','none');
    if ~isempty(legH), legend(ax, legH, legN, 'Location','eastoutside','Interpreter','none','FontSize',9); else, legend(ax,'off'); end
end
function setAll3D(hF, val), S = guidata(hF); for k=1:S.nM, S.cb(k).Value = val; end, updTraj3D(hF); end
