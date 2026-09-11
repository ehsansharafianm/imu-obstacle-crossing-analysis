clc
clearvars -except TN
close all
addpath(fileparts(mfilename('fullpath')));

%% ========================================================================
%% STEP 7 - Leading/Trailing features for ALL signals + camera trajectories
%% ========================================================================
% Classifies every gait cycle by obstacle type and by Leading/Trailing limb, then
% plots and exports all signals (IMU angles, joint angles, ZHC foot height, and the
% step-5 CAMERA foot-marker heights) grouped by Left/Right and by Leading/Trailing.
%
% LABEL SOURCE (new): the obstacle crossings and the leading/trailing leg come from
% the CAMERA - step 3's testN_crossings.xlsx (obstacle_code + lead/trail leg + y=0
% crossing times). Each crossing time is put on the IMU clock (t_cam + step-5 shift)
% and matched to the ZVP stride it lands in: the leading foot's stride (containing
% lead_cross_s) is tagged Leading, the trailing foot's stride (trail_cross_s) Trailing,
% both with the obstacle type W{width}_H{height}. The app FeatureLog is used ONLY for
% the Level_Walk baseline strides; the Dot "Logger Subject" leading-leg log is no
% longer used. (This replaces the old app-terrain + Logger approach; step 5 removed.)

%% ===================== SETTINGS =====================
FONT_NAME     = 'Arial';
% Obstacle groups use the step-3 code = [width][height] (width 1=5cm,2=15cm;
% height 1/2/3 = 10/20/30% of leg length). Width first, height second - consistent
% with step 3. e.g. code 21 -> W2_H1.
TERRAIN_ORDER = {'Level_Walk','W1_H1','W1_H2','W1_H3','W2_H1','W2_H2','W2_H3'};
LOG_PKT_TOL   = 1500;   % max packet distance to match a window to a crossing

%% ===================== INPUT =====================
% Set TN before running (e.g. `TN = 22;`) to skip the prompt for batch runs.
if exist('TN','var') && ~isempty(TN), tn = TN; else, tn = input('  Input Test Number: '); end
root = projectRoot();
dataDir = fullfile(root,'Data','Dot IMUs', ['Test ' num2str(tn)]);
if ~isfolder(dataDir), error('Not found: %s', dataDir); end
feet = {'IMU1','Left Foot'; 'IMU2','Right Foot'};

%% ===================== LOAD SYNCED DATA + SEGMENTS + CAMERA =====================
base    = fullfile(root,'Results','Parameters Output', ['Test ' num2str(tn)]);
allFile = fullfile(base, sprintf('AllData_Test%d.mat', tn));
segFile = fullfile(base, sprintf('SegmentedParams_Test%d.mat', tn));
if ~isfile(allFile) || ~isfile(segFile)
    error('AllData/SegmentedParams for Test %d not found - run step 3 and step 4 first.', tn);
end
Sd = load(allFile,'Data'); Data = Sd.Data;
Sg = load(segFile,'Seg');  Seg  = Sg.Seg;
camFile = fullfile(base, sprintf('CameraSynced_Test%d.mat', tn));
hasCam  = isfile(camFile);
if ~hasCam, error('No %s - run step 5 first (the camera crossings need the sync).', camFile); end
Sc = load(camFile,'Cam'); Cam = Sc.Cam;
shift = 0;
if isfield(Cam,'sync') && isfield(Cam.sync,'shift_s') && ~isempty(Cam.sync.shift_s), shift = Cam.sync.shift_s; end
fprintf('  Camera->IMU sync shift = %+.3f s (from step 5).\n', shift);
zvpL = Seg.zvpL;  zvpR = Seg.zvpR;  tt = Data.time;
iLDot = find(strcmp({Data.imu.label},'Left Foot (Dot)'),1);
iRDot = find(strcmp({Data.imu.label},'Right Foot (Dot)'),1);
if isempty(iLDot) || isempty(iRDot), error('Left/Right Foot (Dot) IMU not found in Data.'); end
pktL = Data.imu(iLDot).packet;  pktR = Data.imu(iRDot).packet;

%% ===================== LEVEL_WALK labels from the app FeatureLog =====================
% App terrain labels are now trusted ONLY for LEVEL WALK (a clean baseline set).
% Obstacle crossings + leading/trailing come from the CAMERA (below), not the app.
Feat = struct('label',{'Left Foot','Right Foot'},'terrain',{{},{}}, ...
              'startPkt',{[],[]},'endPkt',{[],[]},'height',{[],[]},'stride',{[],[]});
feetLbl = {'IMU1','Left Foot'; 'IMU2','Right Foot'};
for f = 1:2
    fp = findFile(dataDir, ['FeatureLog_' feetLbl{f,1} '_*.csv']);
    if isempty(fp), warning('No FeatureLog for %s (%s) - no Level_Walk from app.', feetLbl{f,2}, feetLbl{f,1}); continue; end
    T = readtable(fp);  gt = string(T.Ground_Truth);
    keep = gt == "Level_Walk";
    Feat(f).terrain  = cellstr(gt(keep));
    Feat(f).startPkt = T.Start_Packet(keep);
    Feat(f).endPkt   = T.End_Packet(keep);
    Feat(f).height   = T.Max_Height_m(keep);
    Feat(f).stride   = T.Max_Stride_Length_m(keep);
    fprintf('  %-12s <- %d Level_Walk windows (app)\n', feetLbl{f,2}, nnz(keep));
end

%% ===================== OBSTACLE CROSSINGS + LEADING/TRAILING from the CAMERA =====================
% Read step-3's labelled crossings, map each crossing's y=0 time to the IMU clock
% (t_cam + shift), find the stride it lands in on the leading and trailing feet,
% and synthesise obstacle windows + a leading-leg log entry - so the rest of step 7
% (viewers, export) runs exactly as before, now driven by the camera.
crossXls = fullfile(base, sprintf('test%d_crossings.xlsx', tn));
if ~isfile(crossXls), error('No camera crossings file: %s (run step 3 for this test).', crossXls); end
C = readtable(crossXls,'Sheet','crossings','VariableNamingRule','preserve');
logE = struct('terr',{},'lead',{},'s',{},'e',{});
nUse=0; nUnlab=0; nNoCyc=0; nSpanBad=0;
for r = 1:height(C)
    code = strtrim(char(string(C.obstacle_code(r))));
    if isempty(regexp(code,'^\d\d$','once')), nUnlab = nUnlab + 1; continue; end   % not labelled -> skip
    ll = pickSide(C.lead_leg(r));  tl = pickSide(C.trail_leg(r));
    lct = C.lead_cross_s(r);  tct = C.trail_cross_s(r);
    if ll==' ' || isnan(lct), nNoCyc = nNoCyc + 1; continue; end                   % no leading crossing
    terr = sprintf('W%s_H%s', code(1), code(2));
    zvM = struct('L',zvpL,'R',zvpR);  pkM = struct('L',pktL,'R',pktR);
    pkH = struct('L', C.L_peakz_mm(r)/1000, 'R', C.R_peakz_mm(r)/1000);
    sAll=[]; eAll=[]; usedThis=false;
    % leading foot: the stride containing this foot's y=0 crossing
    [cL, okL] = cycleAtTime(zvM.(ll), tt, lct+shift);
    if okL
        aP = pkM.(ll)(zvM.(ll)(cL));  bP = pkM.(ll)(zvM.(ll)(cL+1));  fi = 1 + (ll=='R');
        Feat(fi).terrain{end+1}=terr; Feat(fi).startPkt(end+1)=aP; Feat(fi).endPkt(end+1)=bP;
        Feat(fi).height(end+1)=pkH.(ll); Feat(fi).stride(end+1)=NaN;
        sAll(end+1)=aP; eAll(end+1)=bP; usedThis=true; %#ok<SAGROW>
        if ~spans0(Cam, ll, zvM.(ll)(cL), zvM.(ll)(cL+1)), nSpanBad = nSpanBad + 1; end
    end
    % trailing foot: the stride containing this foot's y=0 crossing
    if tl~=' ' && ~isnan(tct)
        [cT, okT] = cycleAtTime(zvM.(tl), tt, tct+shift);
        if okT
            aP = pkM.(tl)(zvM.(tl)(cT));  bP = pkM.(tl)(zvM.(tl)(cT+1));  fi = 1 + (tl=='R');
            Feat(fi).terrain{end+1}=terr; Feat(fi).startPkt(end+1)=aP; Feat(fi).endPkt(end+1)=bP;
            Feat(fi).height(end+1)=pkH.(tl); Feat(fi).stride(end+1)=NaN;
            sAll(end+1)=aP; eAll(end+1)=bP; %#ok<SAGROW>
        end
    end
    if ~usedThis, nNoCyc = nNoCyc + 1; continue; end
    e = numel(logE)+1; logE(e).terr=terr; logE(e).lead=ll; logE(e).s=min(sAll); logE(e).e=max(eAll);
    nUse = nUse + 1;
end
fprintf('  Camera crossings: %d used, %d unlabelled (skipped), %d without a matching IMU stride.\n', nUse, nUnlab, nNoCyc);
if nSpanBad > 0, fprintf('  NOTE: %d leading stride(s) whose camera y did not clearly cross 0 - review in the viewer.\n', nSpanBad); end
if nUse == 0, warning('No labelled camera crossings mapped to strides - did you label them in step 3?'); end

%% ===================== FULL TERRAIN SET =====================
terrains   = TERRAIN_ORDER;                              % canonical, even if empty
obsTerr    = TERRAIN_ORDER(~strcmp(TERRAIN_ORDER,'Level_Walk'));   % obstacles only

%% ===================== FEATURE SUMMARY =====================
fprintf('\n=== Feature summary (Test %d): mean +/- SD ===\n', tn);
for k = 1:numel(Feat)
    fprintf('\n  %s\n', Feat(k).label);
    fprintf('    %-16s %5s   %14s   %14s\n', 'Terrain','n','Stride(m)','Height(m)');
    for ti = 1:numel(obsTerr)
        sel = strcmp(Feat(k).terrain, obsTerr{ti});
        if ~any(sel), continue; end
        s = Feat(k).stride(sel);  h = Feat(k).height(sel);
        fprintf('    %-16s %5d   %6.3f+/-%-5.3f   %6.3f+/-%-5.3f\n', obsTerr{ti}, nnz(sel), ...
                mean(s,'omitnan'), std(s,'omitnan'), mean(h,'omitnan'), std(h,'omitnan'));
    end
end

%% ===================== SEGMENT SETUP =====================
% (Data, Seg and Cam were loaded above, with the camera crossings.)
NSEG = Seg.nseg;
pctv = linspace(0,100,NSEG)';
% Time-domain grid: raw samples per cycle, padded to the longest cycle; relative
% time (0 s at each cycle start).
dtt  = median(diff(tt));
mlen = 1;
if numel(zvpL) >= 2, mlen = max(mlen, max(diff(zvpL))+1); end
if numel(zvpR) >= 2, mlen = max(mlen, max(diff(zvpR))+1); end
tvec = (0:mlen-1)' * dtt;

% ZHC foot-height trajectories from step 4 (height = Z / column 3), one column per
% cycle so they line up with terrL/terrR + roleL/roleR just like the other signals.
%   Hg* = normalized (0-100%, NSEG rows),  Ht* = time-domain (padded to mlen rows).
hasZHC = isfield(Seg,'zhc');
HgL=[]; HgR=[]; HtL=[]; HtR=[]; HdL=[]; HdR=[]; xTz=tvec;  distAxis=(0:NSEG-1)';
if hasZHC
    nWinL = max(numel(zvpL)-1,0);  nWinR = max(numel(zvpR)-1,0);
    HgL = zheight(Seg.zhc.L.posGait, nWinL);   % NSEG x nWin
    HgR = zheight(Seg.zhc.R.posGait, nWinR);
    HtL = zheight(Seg.zhc.L.posTime, nWinL);   % mlen x nWin
    HtR = zheight(Seg.zhc.R.posTime, nWinR);
    nR  = min([numel(tvec), size(HtL,1), size(HtR,1)]);       % align time rows to tvec
    xTz = tvec(1:nR);  HtL = HtL(1:nR,:);  HtR = HtR(1:nR,:);
    % Height vs horizontal (XY) distance: shared distance grid across both feet,
    % each cycle's height resampled onto it (height = Z, distance = XY arc length).
    maxD = max(maxHorizDist(Seg.zhc.L.posGait, nWinL), maxHorizDist(Seg.zhc.R.posGait, nWinR));
    if maxD <= 0, maxD = 1; end
    distAxis = linspace(0, maxD, NSEG)';
    HdL = heightPerDistance(Seg.zhc.L.posGait, nWinL, distAxis);   % NSEG x nWin
    HdR = heightPerDistance(Seg.zhc.R.posGait, nWinR, distAxis);
end

% ---- Camera foot-marker height (Z) segmented per cycle (step 5 data) ----
% Same ZVP windows as everything else: Left markers on zvpL, Right on zvpR.
% Cg* = normalized (0-100%, NSEG rows), Ct* = time-domain (padded to mlen rows).
CgLtoe=[];CgLheel=[];CgRtoe=[];CgRheel=[]; CtLtoe=[];CtLheel=[];CtRtoe=[];CtRheel=[];
if hasCam
    CgLtoe  = segCam(tt, Cam.markers.L_toe(:,3),  zvpL, NSEG);
    CgLheel = segCam(tt, Cam.markers.L_heel(:,3), zvpL, NSEG);
    CgRtoe  = segCam(tt, Cam.markers.R_toe(:,3),  zvpR, NSEG);
    CgRheel = segCam(tt, Cam.markers.R_heel(:,3), zvpR, NSEG);
    CtLtoe  = segAllTime(Cam.markers.L_toe(:,3),  zvpL, mlen);
    CtLheel = segAllTime(Cam.markers.L_heel(:,3), zvpL, mlen);
    CtRtoe  = segAllTime(Cam.markers.R_toe(:,3),  zvpR, mlen);
    CtRheel = segAllTime(Cam.markers.R_heel(:,3), zvpR, mlen);
end

% Segment the signals step 4 plots: IMU X (column 2) + joints (excl hip rotation).
% vY  = normalized (0-100%),  vYt = raw time-domain (padded to mlen).
% sideArr    = each signal's own PHYSICAL side (L/R) - used for L/R grouping.
% cycSideArr = the foot whose ZVP/terrain/role apply to that signal's cycles.
%   For legs/pelvis/sternum this equals the own side; ARM IMUs and shoulder/elbow
%   joints swing with the CONTRALATERAL leg, so they are segmented on - and
%   inherit the terrain/leading-trailing labels of - the OPPOSITE foot.
vY={}; vYt={}; vL={}; sideArr = char([]); cycSideArr = char([]);
for i = 1:numel(Data.imu)
    os = imuSide(Data.imu(i).label);                                     % own physical side
    cs = os;  if isUpperLimb(Data.imu(i).label), cs = otherSide(os); end % segmenting-foot side
    zv = sideZVP(cs, zvpL, zvpR);
    xi = Data.imu(i).euler_ZXY_deg(:,2);
    vY{end+1}  = segAll(tt, xi, zv, NSEG);      %#ok<SAGROW>
    vYt{end+1} = segAllTime(xi, zv, mlen);      %#ok<SAGROW>
    vL{end+1}  = sprintf('IMU: %s X', Data.imu(i).label); %#ok<SAGROW>
    sideArr(end+1)=os;  cycSideArr(end+1)=cs;   %#ok<SAGROW>
end
for j = 1:numel(Data.joints.labels)
    nm = Data.joints.labels{j};
    if contains(nm,'hip_rotation'), continue; end
    os = jointSide(nm);                                                  % own physical side
    cs = os;  if isUpperLimb(nm), cs = otherSide(os); end                % segmenting-foot side
    zv = sideZVP(cs, zvpL, zvpR);
    yj = Data.joints.angles_deg(:,j);
    vY{end+1}  = segAll(tt, yj, zv, NSEG);      %#ok<SAGROW>
    vYt{end+1} = segAllTime(yj, zv, mlen);      %#ok<SAGROW>
    vL{end+1}  = sprintf('Joint: %s', nm); %#ok<SAGROW>
    sideArr(end+1)=os;  cycSideArr(end+1)=cs;   %#ok<SAGROW>
end
[wlT,wlS,wlE] = footWindows(Feat,'Left Foot');
[wrT,wrS,wrE] = footWindows(Feat,'Right Foot');
iLDot = find(strcmp({Data.imu.label},'Left Foot (Dot)'),1);
iRDot = find(strcmp({Data.imu.label},'Right Foot (Dot)'),1);

%% ============ PLOT (resolve Unknown crossings interactively, if any) ============
% First pass plots the figures; if the log has Unknown crossings, you classify
% each (Left/Right leading) from the figures, then it re-plots with the resolved
% labels. Finally it exports the Excel. No Unknowns -> just plots once + exports.
firstPass = true;
while true
    % --- per-cycle terrain + leading/trailing role (depend on logE) ---
    terrL = repmat({''},1,max(numel(zvpL)-1,0));  roleL = terrL;
    terrR = repmat({''},1,max(numel(zvpR)-1,0));  roleR = terrR;
    if ~isempty(iLDot), [terrL,roleL] = labelStridesLT(zvpL, Data.imu(iLDot).packet, wlT,wlS,wlE, logE, 'L', 1e6, LOG_PKT_TOL); end
    if ~isempty(iRDot), [terrR,roleR] = labelStridesLT(zvpR, Data.imu(iRDot).packet, wrT,wrS,wrE, logE, 'R', 1e6, LOG_PKT_TOL); end

    fprintf('\n=== Leading / Trailing strides per terrain ===\n');
    for u = 1:numel(obsTerr)
        nLead  = sum(strcmp(roleL,'Leading')  & strcmp(terrL,obsTerr{u})) + sum(strcmp(roleR,'Leading')  & strcmp(terrR,obsTerr{u}));
        nTrail = sum(strcmp(roleL,'Trailing') & strcmp(terrL,obsTerr{u})) + sum(strcmp(roleR,'Trailing') & strcmp(terrR,obsTerr{u}));
        nUnk   = sum(strcmp(roleL,'Unknown')  & strcmp(terrL,obsTerr{u})) + sum(strcmp(roleR,'Unknown')  & strcmp(terrR,obsTerr{u}));
        fprintf('  %-16s  Leading:%d  Trailing:%d  Unknown:%d\n', obsTerr{u}, nLead, nTrail, nUnk);
    end

    % --- Figure 1: bars (Left/Right + Leading/Trailing) ---
    iLeft  = find(strcmp({Feat.label},'Left Foot'),  1);
    iRight = find(strcmp({Feat.label},'Right Foot'), 1);
    emptyG = repmat({[]}, 1, numel(terrains));
    if ~isempty(iLeft),  sL = groupBy(Feat(iLeft).terrain, Feat(iLeft).stride, terrains);  hL = groupBy(Feat(iLeft).terrain, Feat(iLeft).height, terrains);  else, sL=emptyG; hL=emptyG; end
    if ~isempty(iRight), sR = groupBy(Feat(iRight).terrain, Feat(iRight).stride, terrains); hR = groupBy(Feat(iRight).terrain, Feat(iRight).height, terrains); else, sR=emptyG; hR=emptyG; end
    nT = numel(terrains);
    sLead=repmat({[]},1,nT); sTrail=repmat({[]},1,nT); hLead=repmat({[]},1,nT); hTrail=repmat({[]},1,nT);
    for k = 1:numel(Feat)
        if strcmp(Feat(k).label,'Right Foot'), sd='R'; else, sd='L'; end
        for w = 1:numel(Feat(k).terrain)
            Tn = Feat(k).terrain{w};
            if strcmpi(Tn,'Level_Walk'), continue; end
            ti = find(strcmp(terrains, Tn),1); if isempty(ti), continue; end
            rl = crossingRole(logE, Tn, (Feat(k).startPkt(w)+Feat(k).endPkt(w))/2, sd, LOG_PKT_TOL);
            if strcmp(rl,'Leading'),      sLead{ti}(end+1)=Feat(k).stride(w);  hLead{ti}(end+1)=Feat(k).height(w);
            elseif strcmp(rl,'Trailing'), sTrail{ti}(end+1)=Feat(k).stride(w); hTrail{ti}(end+1)=Feat(k).height(w); end
        end
    end
    fig1 = figure('Color','w','Name',sprintf('Dot foot features  |  Test %d', tn),'Position',[40 40 1340 880]);
    drawGrouped(subplot(2,2,1), terrains, sL, sR, 'Stride length (m)', sprintf('Stride length - Left vs Right (Test %d)', tn), FONT_NAME, {'Left','Right'});
    drawGrouped(subplot(2,2,2), terrains, hL, hR, 'Max height (m)',     sprintf('Max height - Left vs Right (Test %d)', tn),     FONT_NAME, {'Left','Right'});
    drawGrouped(subplot(2,2,3), terrains, sLead, sTrail, 'Stride length (m)', sprintf('Stride length - Leading vs Trailing (Test %d)', tn), FONT_NAME, {'Leading','Trailing'});
    drawGrouped(subplot(2,2,4), terrains, hLead, hTrail, 'Max height (m)',     sprintf('Max height - Leading vs Trailing (Test %d)', tn),     FONT_NAME, {'Leading','Trailing'});

    % --- Figures 2-5: stride viewers (normalized + time-domain) ---
    % Left/Right (one signal per sensor/joint) - both x-axes share metadata.
    sigsLR = struct('x',{},'Y',{},'label',{},'grp',{},'terr',{},'cyc',{});
    sigsLRt = sigsLR;
    for i = 1:numel(vL)
        cs = cycSideArr(i);  if cs=='R', tc=terrR; else, tc=terrL; end   % terrain of the segmenting foot
        nc = size(vY{i},2);  if numel(tc)~=nc, tc=repmat({''},1,nc); end
        gg = repmat({sideArr(i)},1,nc);  cc = 1:nc;  m = numel(sigsLR)+1;  % group by physical side
        sigsLR(m).x=pctv;  sigsLR(m).Y=vY{i};   sigsLR(m).label=vL{i};  sigsLR(m).grp=gg; sigsLR(m).terr=tc; sigsLR(m).cyc=cc;
        sigsLRt(m).x=tvec; sigsLRt(m).Y=vYt{i}; sigsLRt(m).label=vL{i}; sigsLRt(m).grp=gg; sigsLRt(m).terr=tc; sigsLRt(m).cyc=cc;
    end
    % Leading/Trailing (Left & Right cycles combined).
    pairMap = containers.Map('KeyType','char','ValueType','any');
    for i = 1:numel(vL)
        bn = baseName(vL{i});
        if ~isKey(pairMap,bn), pairMap(bn)=[NaN NaN]; end
        v = pairMap(bn);  if sideArr(i)=='L', v(1)=i; else, v(2)=i; end  %#ok<SEPEX>
        pairMap(bn)=v;
    end
    sigsLT = struct('x',{},'Y',{},'label',{},'grp',{},'terr',{},'cyc',{});
    sigsLTt = sigsLT;
    ks = keys(pairMap);
    for q = 1:numel(ks)
        v = pairMap(ks{q}); Li=v(1); Ri=v(2);
        if isnan(Li)||isnan(Ri), continue; end
        [ggL,tcL] = roleTerr(cycSideArr(Li), roleL, roleR, terrL, terrR);  % each instance uses its
        [ggR,tcR] = roleTerr(cycSideArr(Ri), roleL, roleR, terrL, terrR);  % own segmenting-foot labels
        gg = [ggL ggR];  tc = [tcL tcR];  cc = [1:size(vY{Li},2), 1:size(vY{Ri},2)];  m = numel(sigsLT)+1;
        sigsLT(m).x=pctv;  sigsLT(m).Y=[vY{Li}  vY{Ri}];  sigsLT(m).label=ks{q}; sigsLT(m).grp=gg; sigsLT(m).terr=tc; sigsLT(m).cyc=cc;
        sigsLTt(m).x=tvec; sigsLTt(m).Y=[vYt{Li} vYt{Ri}]; sigsLTt(m).label=ks{q}; sigsLTt(m).grp=gg; sigsLTt(m).terr=tc; sigsLTt(m).cyc=cc;
    end
    defLR = {'IMU: Left Foot (Dot) X','IMU: Right Foot (Dot) X'};
    defLT = {'IMU: Foot (Dot) X'};
    fig2 = buildGroupViewer(sprintf('Step 7 - Left vs Right (gait %%) | Test %d', tn), sigsLR, defLR, ...
                            FONT_NAME, base, tn, terrains, TERRAIN_ORDER, {'L','R'}, 'LR', false, false, 'terrain', 'Gait cycle (%)', 100);
    fig3 = buildGroupViewer(sprintf('Step 7 - Leading vs Trailing (gait %%) | Test %d', tn), sigsLT, defLT, ...
                            FONT_NAME, base, tn, obsTerr, TERRAIN_ORDER, {'Leading','Trailing','Unknown'}, 'LeadTrail', true, true, 'group', 'Gait cycle (%)', 100);
    fig4 = buildGroupViewer(sprintf('Step 7 - Left vs Right (time) | Test %d', tn), sigsLRt, defLR, ...
                            FONT_NAME, base, tn, terrains, TERRAIN_ORDER, {'L','R'}, 'LR_time', false, false, 'terrain', 'Time (s)', tvec(end));
    fig5 = buildGroupViewer(sprintf('Step 7 - Leading vs Trailing (time) | Test %d', tn), sigsLTt, defLT, ...
                            FONT_NAME, base, tn, obsTerr, TERRAIN_ORDER, {'Leading','Trailing','Unknown'}, 'LeadTrail_time', true, true, 'group', 'Time (s)', tvec(end));

    % --- Figures 6-9: ZHC height-trajectory viewers (same template as 2-5) ---
    trajFigs = [];
    if hasZHC
        % Left/Right: one trajectory signal per foot (colour = terrain).
        trLR  = struct('x',{},'Y',{},'label',{},'grp',{},'terr',{},'cyc',{});  trLRt = trLR;
        trLR(1).x=pctv; trLR(1).Y=HgL; trLR(1).label='ZHC Height: Left Foot';  trLR(1).grp=repmat({'L'},1,size(HgL,2)); trLR(1).terr=terrL; trLR(1).cyc=1:size(HgL,2);
        trLR(2).x=pctv; trLR(2).Y=HgR; trLR(2).label='ZHC Height: Right Foot'; trLR(2).grp=repmat({'R'},1,size(HgR,2)); trLR(2).terr=terrR; trLR(2).cyc=1:size(HgR,2);
        trLRt(1).x=xTz; trLRt(1).Y=HtL; trLRt(1).label='ZHC Height: Left Foot';  trLRt(1).grp=repmat({'L'},1,size(HtL,2)); trLRt(1).terr=terrL; trLRt(1).cyc=1:size(HtL,2);
        trLRt(2).x=xTz; trLRt(2).Y=HtR; trLRt(2).label='ZHC Height: Right Foot'; trLRt(2).grp=repmat({'R'},1,size(HtR,2)); trLRt(2).terr=terrR; trLRt(2).cyc=1:size(HtR,2);
        % Leading/Trailing: Left & Right cycles combined into one signal.
        trLT  = struct('x',pctv,'Y',[HgL HgR],'label','ZHC Height: Foot', ...
                       'grp',{[roleL roleR]},'terr',{[terrL terrR]},'cyc',[1:size(HgL,2), 1:size(HgR,2)]);
        trLTt = struct('x',xTz,'Y',[HtL HtR],'label','ZHC Height: Foot', ...
                       'grp',{[roleL roleR]},'terr',{[terrL terrR]},'cyc',[1:size(HtL,2), 1:size(HtR,2)]);
        defTr  = {'ZHC Height: Left Foot','ZHC Height: Right Foot'};  defTr1 = {'ZHC Height: Foot'};
        fig6 = buildGroupViewer(sprintf('Step 7 - Trajectory Left vs Right (gait %%) | Test %d', tn), trLR, defTr, ...
                                FONT_NAME, base, tn, terrains, TERRAIN_ORDER, {'L','R'}, 'TrajLR', false, false, 'terrain', 'Gait cycle (%)', 100, 'Height (m)', true);
        fig7 = buildGroupViewer(sprintf('Step 7 - Trajectory Leading vs Trailing (gait %%) | Test %d', tn), trLT, defTr1, ...
                                FONT_NAME, base, tn, obsTerr, TERRAIN_ORDER, {'Leading','Trailing','Unknown'}, 'TrajLeadTrail', true, true, 'group', 'Gait cycle (%)', 100, 'Height (m)', true);
        fig8 = buildGroupViewer(sprintf('Step 7 - Trajectory Left vs Right (time) | Test %d', tn), trLRt, defTr, ...
                                FONT_NAME, base, tn, terrains, TERRAIN_ORDER, {'L','R'}, 'TrajLR_time', false, false, 'terrain', 'Time (s)', xTz(end), 'Height (m)', true);
        fig9 = buildGroupViewer(sprintf('Step 7 - Trajectory Leading vs Trailing (time) | Test %d', tn), trLTt, defTr1, ...
                                FONT_NAME, base, tn, obsTerr, TERRAIN_ORDER, {'Leading','Trailing','Unknown'}, 'TrajLeadTrail_time', true, true, 'group', 'Time (s)', xTz(end), 'Height (m)', true);
        % Height vs horizontal distance (foot-clearance-over-distance).
        hdLR  = struct('x',{},'Y',{},'label',{},'grp',{},'terr',{},'cyc',{});
        hdLR(1).x=distAxis; hdLR(1).Y=HdL; hdLR(1).label='ZHC Height: Left Foot';  hdLR(1).grp=repmat({'L'},1,size(HdL,2)); hdLR(1).terr=terrL; hdLR(1).cyc=1:size(HdL,2);
        hdLR(2).x=distAxis; hdLR(2).Y=HdR; hdLR(2).label='ZHC Height: Right Foot'; hdLR(2).grp=repmat({'R'},1,size(HdR,2)); hdLR(2).terr=terrR; hdLR(2).cyc=1:size(HdR,2);
        hdLT  = struct('x',distAxis,'Y',[HdL HdR],'label','ZHC Height: Foot', ...
                       'grp',{[roleL roleR]},'terr',{[terrL terrR]},'cyc',[1:size(HdL,2), 1:size(HdR,2)]);
        fig10 = buildGroupViewer(sprintf('Step 7 - Height vs distance Left vs Right | Test %d', tn), hdLR, defTr, ...
                                FONT_NAME, base, tn, terrains, TERRAIN_ORDER, {'L','R'}, 'TrajLR_dist', false, false, 'terrain', 'Horizontal distance (m)', distAxis(end), 'Height (m)', true);
        fig11 = buildGroupViewer(sprintf('Step 7 - Height vs distance Leading vs Trailing | Test %d', tn), hdLT, defTr1, ...
                                FONT_NAME, base, tn, obsTerr, TERRAIN_ORDER, {'Leading','Trailing','Unknown'}, 'TrajLeadTrail_dist', true, true, 'group', 'Horizontal distance (m)', distAxis(end), 'Height (m)', true);
        trajFigs = [fig6 fig7 fig8 fig9 fig10 fig11];
    end

    % --- Figures 12-15: camera marker-height viewers (same template) ---
    camFigs = [];
    if hasCam
        % Left/Right: one signal per marker (colour = terrain).
        camLR = struct('x',{},'Y',{},'label',{},'grp',{},'terr',{},'cyc',{});  camLRt = camLR;
        cmk = {'L_toe',CgLtoe,CtLtoe,'L',terrL; 'L_heel',CgLheel,CtLheel,'L',terrL; ...
               'R_toe',CgRtoe,CtRtoe,'R',terrR; 'R_heel',CgRheel,CtRheel,'R',terrR};
        for c = 1:size(cmk,1)
            nm=['Cam: ' cmk{c,1}]; Yg=cmk{c,2}; Yt=cmk{c,3}; gr=cmk{c,4}; te=cmk{c,5};
            camLR(c).x=pctv; camLR(c).Y=Yg; camLR(c).label=nm; camLR(c).grp=repmat({gr},1,size(Yg,2)); camLR(c).terr=te; camLR(c).cyc=1:size(Yg,2);
            camLRt(c).x=tvec; camLRt(c).Y=Yt; camLRt(c).label=nm; camLRt(c).grp=repmat({gr},1,size(Yt,2)); camLRt(c).terr=te; camLRt(c).cyc=1:size(Yt,2);
        end
        % Leading/Trailing: pair each marker type across sides (Left & Right cycles combined).
        camLT  = struct('x',pctv,'Y',{[CgLtoe CgRtoe]}, 'label','Cam: toe', 'grp',{[roleL roleR]},'terr',{[terrL terrR]},'cyc',[1:size(CgLtoe,2),1:size(CgRtoe,2)]);
        camLT(2)= struct('x',pctv,'Y',[CgLheel CgRheel],'label','Cam: heel','grp',{[roleL roleR]},'terr',{[terrL terrR]},'cyc',[1:size(CgLheel,2),1:size(CgRheel,2)]);
        camLTt  = struct('x',tvec,'Y',{[CtLtoe CtRtoe]}, 'label','Cam: toe', 'grp',{[roleL roleR]},'terr',{[terrL terrR]},'cyc',[1:size(CtLtoe,2),1:size(CtRtoe,2)]);
        camLTt(2)= struct('x',tvec,'Y',[CtLheel CtRheel],'label','Cam: heel','grp',{[roleL roleR]},'terr',{[terrL terrR]},'cyc',[1:size(CtLheel,2),1:size(CtRheel,2)]);
        defCamLR = {'Cam: L_toe','Cam: R_toe'};  defCamLT = {'Cam: toe'};
        figC1 = buildGroupViewer(sprintf('Step 7 - Camera Left vs Right (gait %%) | Test %d', tn), camLR, defCamLR, ...
                                 FONT_NAME, base, tn, terrains, TERRAIN_ORDER, {'L','R'}, 'CamLR', false, false, 'terrain', 'Gait cycle (%)', 100, 'Height (mm)', true);
        figC2 = buildGroupViewer(sprintf('Step 7 - Camera Leading vs Trailing (gait %%) | Test %d', tn), camLT, defCamLT, ...
                                 FONT_NAME, base, tn, obsTerr, TERRAIN_ORDER, {'Leading','Trailing','Unknown'}, 'CamLeadTrail', true, true, 'group', 'Gait cycle (%)', 100, 'Height (mm)', true);
        figC3 = buildGroupViewer(sprintf('Step 7 - Camera Left vs Right (time) | Test %d', tn), camLRt, defCamLR, ...
                                 FONT_NAME, base, tn, terrains, TERRAIN_ORDER, {'L','R'}, 'CamLR_time', false, false, 'terrain', 'Time (s)', tvec(end), 'Height (mm)', true);
        figC4 = buildGroupViewer(sprintf('Step 7 - Camera Leading vs Trailing (time) | Test %d', tn), camLTt, defCamLT, ...
                                 FONT_NAME, base, tn, obsTerr, TERRAIN_ORDER, {'Leading','Trailing','Unknown'}, 'CamLeadTrail_time', true, true, 'group', 'Time (s)', tvec(end), 'Height (mm)', true);
        camFigs = [figC1 figC2 figC3 figC4];
    end

    allFigs = [fig1 fig2 fig3 fig4 fig5 trajFigs camFigs];
    drawnow;

    % --- resolve Unknown crossings (first pass only) ---
    uLead = [logE.lead];  unk = find(uLead == 'U');
    if firstPass && ~isempty(unk)
        firstPass = false;
        fprintf(['\n*** %d Unknown crossing(s) in the log. A "Classify Unknown crossings" figure\n' ...
                 '    highlights the two candidate cycles (blue = Left, red = Right) for the one\n' ...
                 '    you are answering; classify each below. ***\n'], numel(unk));
        figDec = figure('Color','w','Name','Classify Unknown crossings','Position',[120 120 1120 470]);
        anyAsked = false;
        for q = 1:numel(unk)
            i = unk(q);
            ctr = (logE(i).s + logE(i).e)/2;
            lc = cycleForCrossing(Feat,'Left Foot',  Data, iLDot, zvpL, logE(i).terr, ctr, 1e6);
            rc = cycleForCrossing(Feat,'Right Foot', Data, iRDot, zvpR, logE(i).terr, ctr, 1e6);
            if isnan(lc) && isnan(rc)
                fprintf('  (skipping Unknown %s pkt %d-%d: no matching cycle in this trial)\n', logE(i).terr, logE(i).s, logE(i).e);
                continue;
            end
            drawDecision(figDec, q, numel(unk), logE(i), lc, rc, vL, vY, pctv);  drawnow;
            logE(i).lead = askLead(q, numel(unk), logE(i), lc, rc);
            anyAsked = true;
        end
        if ishghandle(figDec), close(figDec); end
        if anyAsked
            close(allFigs);
            continue;                 % re-plot with the resolved (uniform) labels
        end
        break;                        % nothing classifiable -> keep figures, export
    end
    break;
end

%% ===================== EXPORT (final labels) =====================
exportWindowsLT(base, tn, Feat, Data, zvpL, zvpR, iLDot, iRDot, logE, LOG_PKT_TOL, 1e6);

%% ===================== SAVE SEGMENTED TRAJECTORIES (.mat) =====================
% One entry per sensor/joint (Left & Right cycles combined), each cycle tagged
% with its side, terrain, leading/trailing role and cycle number, so downstream
% code can slice trajectories by label and by leading/trailing. See README.md
% ("Accessing step-5 results") for the layout and examples.
S5 = struct('test', tn, 'pct', pctv, 'time', tvec, 'terrains', {TERRAIN_ORDER});
bmap = containers.Map('KeyType','char','ValueType','any');  border = {};
for i = 1:numel(vL)
    bn = baseName(vL{i});
    if ~isKey(bmap, bn), bmap(bn) = []; border{end+1} = bn; end %#ok<SAGROW>
    bmap(bn) = [bmap(bn), i];
end
sig = struct('name',{},'Y',{},'Yt',{},'side',{},'terrain',{},'role',{},'cycle',{});
for q = 1:numel(border)
    Y=[]; Yt=[]; sideC={}; terrC={}; roleC={}; cycC=[];
    for i = bmap(border{q})
        sd = sideArr(i);  cs = cycSideArr(i);   % sd = physical sensor side; cs = segmenting foot
        if cs == 'R', tc = terrR; rc = roleR; else, tc = terrL; rc = roleL; end
        nc = size(vY{i},2);
        if numel(tc) ~= nc, tc = repmat({''},1,nc); rc = repmat({''},1,nc); end
        Y     = [Y, vY{i}];                  %#ok<AGROW>
        Yt    = [Yt, vYt{i}];                %#ok<AGROW>
        sideC = [sideC, repmat({sd},1,nc)];  %#ok<AGROW>
        terrC = [terrC, tc];                 %#ok<AGROW>
        roleC = [roleC, rc];                 %#ok<AGROW>
        cycC  = [cycC, 1:nc];                %#ok<AGROW>
    end
    m = numel(sig) + 1;
    sig(m).name = border{q};  sig(m).Y = Y;  sig(m).Yt = Yt;  sig(m).side = sideC;
    sig(m).terrain = terrC;   sig(m).role = roleC;  sig(m).cycle = cycC;
end
if hasZHC
    % ZHC foot-height trajectory as one more signal (metres, not degrees).
    m = numel(sig) + 1;
    sig(m).name    = 'ZHC Height: Foot';
    sig(m).Y       = [HgL HgR];      sig(m).Yt   = [HtL HtR];
    sig(m).side    = [repmat({'L'},1,size(HgL,2)), repmat({'R'},1,size(HgR,2))];
    sig(m).terrain = [terrL terrR];  sig(m).role = [roleL roleR];
    sig(m).cycle   = [1:size(HgL,2), 1:size(HgR,2)];
end
S5.signal = sig;          % .Y = normalized (S5.pct), .Yt = time-domain (S5.time)
S5.Feat   = Feat;         % per-window features (terrain, packets, height, stride)
S5.log    = logE;         % leading-leg crossings parsed from the Logger
if hasZHC
    % Full ZHC foot-trajectory set, tagged per cycle by terrain and role so it can
    % be sliced exactly like S5.signal. See README ("ZHC foot trajectories").
    S5.zhc.L = Seg.zhc.L;   % per-cycle posTime/posGait (X Y Z) + whole path (tCont/pCont) + ZVP markers
    S5.zhc.R = Seg.zhc.R;
    S5.zhc.terrainL = terrL;  S5.zhc.roleL = roleL;    % 1 x nCycles labels (Left foot)
    S5.zhc.terrainR = terrR;  S5.zhc.roleR = roleR;    % 1 x nCycles labels (Right foot)
    S5.zhc.height_gait = struct('L', HgL, 'R', HgR);   % height only, NSEG x cycles (0-100%)
    S5.zhc.height_time = struct('L', HtL, 'R', HtR);   % height only, mlen x cycles (time)
    S5.zhc.height_dist = struct('L', HdL, 'R', HdR);   % height only, NSEG x cycles (vs distance)
    S5.zhc.time = xTz;                                 % time axis (s)  for height_time
    S5.zhc.dist = distAxis;                            % distance axis (m) for height_dist
    % Combined, per-cycle-tagged table (Left then Right) - the one-stop input for
    % step 5 statistics: every cycle labelled by side/terrain/role, with its height
    % in all three domains (gait %, time, distance) as column-aligned matrices.
    S5.zhc.all.side    = [repmat({'L'},1,size(HgL,2)), repmat({'R'},1,size(HgR,2))];
    S5.zhc.all.terrain = [terrL terrR];
    S5.zhc.all.role    = [roleL roleR];
    S5.zhc.all.cycle   = [1:size(HgL,2), 1:size(HgR,2)];
    S5.zhc.all.Hgait   = [HgL HgR];   % NSEG x cycles  (x = S5.pct)
    S5.zhc.all.Htime   = [HtL HtR];   % mlen x cycles  (x = S5.zhc.time)
    S5.zhc.all.Hdist   = [HdL HdR];   % NSEG x cycles  (x = S5.zhc.dist)
    S5.zhc.all.peak    = max([HgL HgR], [], 1, 'omitnan');   % 1 x cycles, peak clearance (m)
end
if hasCam
    % Camera marker heights (mm), per cycle, tagged by side/terrain/role like the rest.
    S5.camera.pct = pctv;  S5.camera.time = tvec;
    S5.camera.terrainL = terrL;  S5.camera.roleL = roleL;
    S5.camera.terrainR = terrR;  S5.camera.roleR = roleR;
    S5.camera.height_gait = struct('L_toe',CgLtoe,'L_heel',CgLheel,'R_toe',CgRtoe,'R_heel',CgRheel);
    S5.camera.height_time = struct('L_toe',CtLtoe,'L_heel',CtLheel,'R_toe',CtRtoe,'R_heel',CtRheel);
    % Combined table (Left then Right), one column per cycle - toe & heel height.
    S5.camera.all.side    = [repmat({'L'},1,size(CgLtoe,2)), repmat({'R'},1,size(CgRtoe,2))];
    S5.camera.all.terrain = [terrL terrR];
    S5.camera.all.role    = [roleL roleR];
    S5.camera.all.toe_gait  = [CgLtoe CgRtoe];    S5.camera.all.heel_gait = [CgLheel CgRheel];
    S5.camera.all.toe_peak  = max([CgLtoe CgRtoe], [], 1, 'omitnan');   % 1 x cycles, peak toe height (mm)
end
matFile = fullfile(base, sprintf('SegTrajectories_WithCamera_Test%d.mat', tn));
save(matFile, 'S5');
fprintf('Saved segmented trajectories (incl. camera) to:\n  %s\n', matFile);

%% ========================================================================
%  LOCAL FUNCTIONS
%% ========================================================================
function g = groupBy(terr, val, terrains)
    g = cell(1, numel(terrains));
    for k = 1:numel(terrains), g{k} = val(strcmp(terr, terrains{k})); end
end

function [terr, sp, ep, h, st] = dedupHeight(terr, sp, ep, h, st)
% Keep the higher Max_Height_m among a run of consecutive contiguous windows
% with the same Height*_Depth* label (no packet gap between them).
    GAP_TOL = 5;
    n = numel(terr);  keep = true(n,1);
    isH = cellfun(@(s) contains(s,'Depth'), terr);
    i = 1;
    while i <= n
        if isH(i)
            j = i;
            while j+1 <= n && isH(j+1) && strcmp(terr{j+1}, terr{i}) ...
                    && abs(sp(j+1) - ep(j)) <= GAP_TOL
                j = j + 1;
            end
            if j > i
                [~, rel] = max(h(i:j));
                keep(i:j) = false;  keep(i + rel - 1) = true;
            end
            i = j + 1;
        else
            i = i + 1;
        end
    end
    terr = terr(keep);  sp = sp(keep);  ep = ep(keep);  h = h(keep);  st = st(keep);
end

function drawGrouped(ax, terrains, vL, vR, ylab, ttl, fn, legLabels)
    if nargin < 8 || isempty(legLabels), legLabels = {'Left','Right'}; end
    nT = numel(terrains);
    mL=nan(1,nT); sdL=nan(1,nT); mR=nan(1,nT); sdR=nan(1,nT);
    for k = 1:nT
        if ~isempty(vL{k}), mL(k)=mean(vL{k},'omitnan'); sdL(k)=std(vL{k},'omitnan'); end
        if ~isempty(vR{k}), mR(k)=mean(vR{k},'omitnan'); sdR(k)=std(vR{k},'omitnan'); end
    end
    cL = [0.20 0.50 0.90]; cR = [0.90 0.50 0.20];
    axes(ax); hold(ax,'on'); grid(ax,'on'); box(ax,'on');
    b = bar(ax, 1:nT, [mL; mR]', 'grouped');
    b(1).FaceColor = cL;  b(2).FaceColor = cR;
    xL = b(1).XEndPoints;  xR = b(2).XEndPoints;
    errorbar(ax, xL, mL, sdL, 'k', 'LineStyle','none', 'CapSize', 6, 'LineWidth', 1);
    errorbar(ax, xR, mR, sdR, 'k', 'LineStyle','none', 'CapSize', 6, 'LineWidth', 1);
    for k = 1:nT
        if ~isempty(vL{k}), scatter(ax, xL(k)+(rand(numel(vL{k}),1)-0.5)*0.06, vL{k}(:), 14, cL*0.7, 'filled'); end
        if ~isempty(vR{k}), scatter(ax, xR(k)+(rand(numel(vR{k}),1)-0.5)*0.06, vR{k}(:), 14, cR*0.7, 'filled'); end
    end
    set(ax, 'XTick', 1:nT, 'XTickLabel', terrains, 'TickLabelInterpreter', 'none');  xtickangle(ax, 30);
    xlim(ax, [0.5 nT+0.5]);
    ax.FontName = fn; ax.FontSize = 11; ax.FontWeight = 'bold';
    ylabel(ax, ylab, 'FontSize', 13, 'FontWeight','bold', 'FontName', fn);
    title(ax, ttl, 'FontSize', 14, 'FontName', fn, 'Interpreter','none');
    legend(ax, legLabels, 'Location','best');
end

function fp = findFile(dataDir, pattern)
    d = dir(fullfile(dataDir, pattern));
    if isempty(d), fp = ''; else, fp = fullfile(dataDir, d(1).name); end
end

function root = projectRoot()
    cand = {};
    sd = fileparts(mfilename('fullpath'));
    if ~isempty(sd), cand{end+1} = fileparts(sd); end
    cand{end+1} = fileparts(pwd);  cand{end+1} = pwd;
    for i = 1:numel(cand)
        if isProjectRoot(cand{i}), root = cand{i}; return; end
    end
    fprintf(2, '  Could not find the project folder relative to the script.\n');
    while true
        root = input('  Enter the full path to the folder that contains ''Data'' and ''Results'': ', 's');
        root = regexprep(strtrim(root), '^["'']|["'']$', '');
        if isProjectRoot(root), return; end
        fprintf(2, '  ''%s'' has no Data%sDot IMUs folder - try again.\n', root, filesep);
    end
end

function tf = isProjectRoot(p)
    tf = ~isempty(p) && isfolder(fullfile(p,'Data','Dot IMUs'));
end

%% ----- log parsing + window/cycle/role matching -----
function logE = readLeadLog(dataDir)
% Parse the Dot "Logger Subject ..." txt for the leading-leg crossing lines.
    logE = struct('terr',{},'lead',{},'s',{},'e',{});
    fp = findFile(dataDir, 'Logger*.txt');
    if isempty(fp), warning('No "Logger*.txt" found in %s - no leading/trailing info.', dataDir); return; end
    txt = fileread(fp);
    pat = 'Leading leg is (Right|Left|Unknown) for (H\d+_D\d+) crossing \(Start pkt:\s*(\d+),\s*End pkt:\s*(\d+)\)';
    toks = regexp(txt, pat, 'tokens');
    for i = 1:numel(toks)
        t = toks{i};
        logE(i).terr = normTerr(t{2});
        logE(i).lead = t{1}(1);          % 'R', 'L', or 'U' (Unknown)
        logE(i).s = str2double(t{3});
        logE(i).e = str2double(t{4});
    end
end

function full = normTerr(short)
% 'H2_D1' -> 'Height2_Depth1'
    full = regexprep(short, '^H(\d+)_D(\d+)$', 'Height$1_Depth$2');
end

function role = crossingRole(logE, terrFull, ctrPkt, side, tol)
% Leading/Trailing for a window centre packet: nearest same-terrain log crossing
% within tol; role depends on whether THIS side is the recorded leading leg.
    role = '';
    best = inf; lead = '';
    for i = 1:numel(logE)
        if ~strcmp(logE(i).terr, terrFull), continue; end
        if ctrPkt >= logE(i).s && ctrPkt <= logE(i).e, d = 0;
        else, d = min(abs(ctrPkt - logE(i).s), abs(ctrPkt - logE(i).e)); end
        if d < best, best = d; lead = logE(i).lead; end
    end
    if isempty(lead) || best > tol, return; end
    if lead == 'U',      role = 'Unknown';     % operator pressed Unknown
    elseif lead == side, role = 'Leading';
    else,                role = 'Trailing';
    end
end

function [terrOf, roleOf] = labelStridesLT(zvp, pkt, winTerr, winS, winE, logE, side, pmod, tol)
% Per-cycle terrain + leading/trailing role. Each window is matched to its best
% step-4 cycle (closest Dot-packet range); obstacle windows also get a role from
% the log. Obstacle labels override Level_Walk on the same cycle.
    [cycS, cycE] = cyclePackets(zvp, pkt, pmod);
    nStr = numel(cycS);
    terrOf = repmat({''},1,nStr);  roleOf = repmat({''},1,nStr);
    if nStr < 1, return; end
    for w = 1:numel(winTerr)
        c = bestCycle(cycS, cycE, mod(winS(w),pmod), mod(winE(w),pmod));
        if isempty(c), continue; end
        if strcmpi(winTerr{w},'Level_Walk')
            if isempty(terrOf{c}), terrOf{c} = winTerr{w}; end
        else
            terrOf{c} = winTerr{w};
            ctr = mod((winS(w)+winE(w))/2, pmod);
            roleOf{c} = crossingRole(logE, winTerr{w}, ctr, side, tol);
        end
    end
end

function [cycS, cycE] = cyclePackets(zvp, pkt, pmod)
    nStr = max(numel(zvp)-1, 0);
    if nStr < 1, cycS = []; cycE = []; return; end
    cycS = mod(pkt(zvp(1:nStr)),   pmod);  cycS = cycS(:);
    cycE = mod(pkt(zvp(2:nStr+1)), pmod);  cycE = cycE(:);
end

function c = bestCycle(cycS, cycE, ws, we)
    a = min(ws,we); b = max(ws,we);
    ov = min(cycE,b) - max(cycS,a);  ov(ov < 0) = 0;
    [mx, c] = max(ov);
    if mx <= 0, [~, c] = min(abs((cycS+cycE)/2 - (a+b)/2)); end
end

function s = pickSide(v)
% Normalise a lead/trail-leg cell value to a single 'L'/'R' char, or ' ' if absent.
    s = upper(strtrim(char(string(v))));
    if isempty(s) || ~(s(1)=='L' || s(1)=='R'), s = ' '; else, s = s(1); end
end

function [c, ok] = cycleAtTime(zvp, tt, T)
% Which ZVP stride contains IMU time T. Strides are contiguous, so any T inside
% [tt(zvp(1)), tt(zvp(end))] lands in exactly one. ok=false if T is outside them.
    c = NaN; ok = false;
    if numel(zvp) < 2 || isnan(T), return; end
    tb = tt(zvp);  tb = tb(:);
    if T < tb(1) || T > tb(end), return; end
    c = find(tb(1:end-1) <= T & T < tb(2:end), 1);
    if isempty(c)
        if T == tb(end), c = numel(tb)-1; else, return; end
    end
    ok = true;
end

function tf = spans0(Cam, side, a, b)
% Does the camera TOE marker on this side cross y=0 within samples a..b? Used only
% to flag crossings whose selected stride looks off (returns true when it can't judge).
    tf = true;
    mk = [side '_toe'];
    if ~isfield(Cam,'markers') || ~isfield(Cam.markers, mk), return; end
    y = Cam.markers.(mk)(a:b, 2);  y = y(isfinite(y));
    if numel(y) < 2, return; end
    tf = (min(y) < 0) && (max(y) > 0);
end

function s = segAll(t, y, zvp, Nseg)
    nStr = max(numel(zvp)-1, 0);
    s = nan(Nseg, max(nStr,1));
    for k = 1:nStr
        a = zvp(k); b = zvp(k+1);
        if b <= a+1, continue; end
        tt = t(a:b); seg = y(a:b); ok = ~isnan(seg);
        if nnz(ok) < 2, continue; end
        s(:,k) = interp1(tt(ok), seg(ok), linspace(tt(1),tt(end),Nseg), 'spline');
    end
end

function A = segAllTime(y, zvp, maxLen)
% Raw (non-normalized) cycles, NaN-padded to maxLen rows. Column index = cycle
% index (no columns dropped, so it lines up with terr/role per cycle).
    nStr = max(numel(zvp)-1, 0);
    A = nan(maxLen, max(nStr,1));
    for k = 1:nStr
        a = zvp(k); b = zvp(k+1);
        if b <= a+1, continue; end
        seg = y(a:b);  nkeep = min(numel(seg), maxLen);
        A(1:nkeep, k) = seg(1:nkeep);
    end
end

function s = sideZVP(side, zvpL, zvpR)
    if side == 'R', s = zvpR; else, s = zvpL; end
end

function s = segCam(t, y, zvp, Nseg)
% Camera-marker cycles normalized to Nseg points. Linear over the finite (non-NaN)
% samples only, NaN outside their range (no spline overshoot on gappy camera data).
% No columns dropped, so the cycle index lines up with terr/role.
    nStr = max(numel(zvp)-1, 0);
    s = nan(Nseg, max(nStr,1));
    for k = 1:nStr
        a = zvp(k); b = zvp(k+1);
        if b <= a+1, continue; end
        tt = t(a:b); seg = y(a:b); ok = ~isnan(seg);
        if nnz(ok) < 2, continue; end
        s(:,k) = interp1(tt(ok), seg(ok), linspace(tt(1),tt(end),Nseg), 'linear');
    end
end

function H = zheight(pos, nWin)
% Pull the Z (height) page out of a ZHC pos array (rows x 3 x cycles) as
% rows x cycles, clamped/padded to nWin columns so it matches the per-cycle labels.
    if isempty(pos), H = nan(1, max(nWin,0)); return; end
    H = squeeze(pos(:,3,:));
    if size(pos,3) == 1, H = pos(:,3);  end     % keep column when only one cycle
    if nWin < 1, H = zeros(size(H,1),0); return; end
    if size(H,2) >= nWin, H = H(:,1:nWin);
    else, H = [H, nan(size(H,1), nWin - size(H,2))]; end
end

function md = maxHorizDist(pos, nWin)
% Longest per-cycle horizontal (XY) path length across the cycles - sets the
% shared distance-axis extent.
    md = 0;
    if isempty(pos) || nWin < 1, return; end
    for c = 1:min(size(pos,3), nWin)
        X = pos(:,1,c); Y = pos(:,2,c);  g = isfinite(X) & isfinite(Y);
        X = X(g); Y = Y(g);
        if numel(X) < 2, continue; end
        md = max(md, sum(sqrt(diff(X).^2 + diff(Y).^2)));
    end
end

function Hd = heightPerDistance(pos, nWin, distAxis)
% Height (Z) as a function of horizontal (XY) distance travelled from cycle start,
% each cycle resampled onto the shared distAxis (NaN beyond its own reach).
    ND = numel(distAxis);
    Hd = nan(ND, max(nWin,0));
    if isempty(pos) || nWin < 1, return; end
    for c = 1:min(size(pos,3), nWin)
        X = pos(:,1,c); Y = pos(:,2,c); Z = pos(:,3,c);
        g = isfinite(X) & isfinite(Y) & isfinite(Z);
        X = X(g); Y = Y(g); Z = Z(g);
        if numel(X) < 2, continue; end
        d = [0; cumsum(sqrt(diff(X).^2 + diff(Y).^2))];   % monotonic arc length
        [du, iu] = unique(d);                             % drop zero-motion repeats
        if numel(du) < 2, continue; end
        Hd(:,c) = interp1(du, Z(iu), distAxis, 'linear', NaN);
    end
end
function s = imuSide(label)
    if contains(label,'Right'), s = 'R'; else, s = 'L'; end
end
function s = jointSide(name)
    if endsWith(name,'_r'), s = 'R'; else, s = 'L'; end
end
function tf = isUpperLimb(s)   % arm IMU label or shoulder/elbow joint name
    s = lower(s);  tf = contains(s,'arm') || contains(s,'elbow');
end
function s = otherSide(s)
    if s == 'R', s = 'L'; else, s = 'R'; end
end
function [r, t] = roleTerr(cs, roleL, roleR, terrL, terrR)
% Role + terrain label arrays of the foot (cs = 'L'/'R') that segmented a signal.
    if cs == 'R', r = roleR; t = terrR; else, r = roleL; t = terrL; end
end
function b = baseName(lbl)
% Strip the side so Left/Right instances of a sensor/joint share a base name.
    b = regexprep(lbl, '(Left|Right)\s', '');   % "IMU: Left Foot (Dot) X" -> "IMU: Foot (Dot) X"
    b = regexprep(b, '_(l|r)$', '');             % "Joint: hip_flexion_l"   -> "Joint: hip_flexion"
end

function [terr, sp, ep] = footWindows(Feat, footLabel)
    terr = {}; sp = []; ep = [];
    k = find(strcmp({Feat.label}, footLabel), 1);
    if isempty(k), return; end
    terr = Feat(k).terrain(:)';  sp = Feat(k).startPkt(:)';  ep = Feat(k).endPkt(:)';
end

%% ----- Excel export -----
function exportWindowsLT(base, tn, Feat, Data, zvpL, zvpR, iLDot, iRDot, logE, tol, pmod)
% Three clear, non-overlapping views:
%   'Left Foot' / 'Right Foot' : one row per obstacle window of THAT physical
%       foot, with a Role column (was this foot Leading or Trailing here?).
%   'Leading vs Trailing'      : one row per CROSSING - the Left & Right windows
%       paired, with the leading and trailing limb spelled out side by side, so
%       there is no overlap/duplication to read through.
    if ~isfolder(base), mkdir(base); end
    xls = fullfile(base, sprintf('WindowFeatures_SideBased_Test%d.xlsx', tn));
    if exist(xls,'file'), delete(xls); end
    PAIR_TOL = 400;        % packets - max start gap to pair a Left & Right window
    feet = {'Left Foot','L',iLDot,zvpL; 'Right Foot','R',iRDot,zvpR};
    rTerr={}; rSide={}; rRole={}; ws=[]; we=[]; cyc=[]; ds=[]; de=[]; cts=[]; cte=[]; hh=[]; ss=[];
    for f = 1:size(feet,1)
        k = find(strcmp({Feat.label}, feet{f,1}), 1);  sd = feet{f,2};  idx = feet{f,3};  zvp = feet{f,4};
        if isempty(k) || isempty(idx) || numel(zvp) < 2, continue; end
        pkt = Data.imu(idx).packet;  t = Data.time;
        [cycS, cycE] = cyclePackets(zvp, pkt, pmod);
        for w = 1:numel(Feat(k).terrain)
            if strcmpi(Feat(k).terrain{w},'Level_Walk'), continue; end
            c   = bestCycle(cycS, cycE, mod(Feat(k).startPkt(w),pmod), mod(Feat(k).endPkt(w),pmod));
            ctr = mod((Feat(k).startPkt(w)+Feat(k).endPkt(w))/2, pmod);
            rl  = crossingRole(logE, Feat(k).terrain{w}, ctr, sd, tol);
            if isempty(rl), rl = '(unmatched)'; end
            rTerr{end+1}=Feat(k).terrain{w}; rSide{end+1}=sd; rRole{end+1}=rl;  %#ok<AGROW>
            ws(end+1)=Feat(k).startPkt(w);   we(end+1)=Feat(k).endPkt(w);       %#ok<AGROW>
            cyc(end+1)=c;  ds(end+1)=cycS(c);  de(end+1)=cycE(c);              %#ok<AGROW>
            cts(end+1)=t(zvp(c));  cte(end+1)=t(zvp(c+1));                     %#ok<AGROW>
            hh(end+1)=Feat(k).height(w);  ss(end+1)=Feat(k).stride(w);         %#ok<AGROW>
        end
    end
    % Level-walk windows (both feet) for a dedicated sheet.
    lwSide={}; lwWs=[]; lwWe=[]; lwCyc=[]; lwDs=[]; lwDe=[]; lwCts=[]; lwCte=[]; lwHh=[]; lwSs=[];
    for f = 1:size(feet,1)
        k = find(strcmp({Feat.label}, feet{f,1}), 1);  sd = feet{f,2};  idx = feet{f,3};  zvp = feet{f,4};
        if isempty(k) || isempty(idx) || numel(zvp) < 2, continue; end
        pkt = Data.imu(idx).packet;  t = Data.time;
        [cycS, cycE] = cyclePackets(zvp, pkt, pmod);
        for w = 1:numel(Feat(k).terrain)
            if ~strcmpi(Feat(k).terrain{w},'Level_Walk'), continue; end
            c = bestCycle(cycS, cycE, mod(Feat(k).startPkt(w),pmod), mod(Feat(k).endPkt(w),pmod));
            lwSide{end+1}=sd; lwWs(end+1)=Feat(k).startPkt(w); lwWe(end+1)=Feat(k).endPkt(w); %#ok<AGROW>
            lwCyc(end+1)=c; lwDs(end+1)=cycS(c); lwDe(end+1)=cycE(c);                          %#ok<AGROW>
            lwCts(end+1)=t(zvp(c)); lwCte(end+1)=t(zvp(c+1));                                  %#ok<AGROW>
            lwHh(end+1)=Feat(k).height(w); lwSs(end+1)=Feat(k).stride(w);                      %#ok<AGROW>
        end
    end
    if isempty(rTerr) && isempty(lwSide), fprintf('No windows to export.\n'); return; end
    nSheets = 0;

    % Pair every Left window with its nearest Right window of the same terrain
    % (within PAIR_TOL). Unmatched singles are kept (other side left blank).
    Li = find(strcmp(rSide,'L'));  Ri = find(strcmp(rSide,'R'));  usedR = false(1,numel(Ri));
    rows = zeros(0,2);                                   % [Lidx Ridx]; 0 = missing
    for a = 1:numel(Li)
        li = Li(a);  bestj = 0;  bestd = inf;
        for b = 1:numel(Ri)
            if usedR(b) || ~strcmp(rTerr{li}, rTerr{Ri(b)}), continue; end
            d = abs(ws(li) - ws(Ri(b)));
            if d < bestd, bestd = d; bestj = b; end
        end
        if bestj > 0 && bestd <= PAIR_TOL, usedR(bestj) = true; rows(end+1,:) = [li, Ri(bestj)]; %#ok<AGROW>
        else, rows(end+1,:) = [li, 0]; end %#ok<AGROW>
    end
    for b = 1:numel(Ri), if ~usedR(b), rows(end+1,:) = [0, Ri(b)]; end; end %#ok<AGROW>
    key = zeros(size(rows,1),1);                         % order by earliest start
    for p = 1:size(rows,1), key(p) = min(ws(rows(p, rows(p,:) > 0))); end
    [~, po] = sort(key);  rows = rows(po,:);

    % --- 'Left and Right' sheet: Left & Right of each crossing side by side ---
    cT={}; LRo={}; Lws=[]; Lwe=[]; Lcy=[]; Lh=[]; Lst=[];
           RRo={}; Rws=[]; Rwe=[]; Rcy=[]; Rh=[]; Rst=[];
    for p = 1:size(rows,1)
        li = rows(p,1);  ri = rows(p,2);
        if li > 0, cT{end+1}=rTerr{li}; else, cT{end+1}=rTerr{ri}; end %#ok<AGROW>
        if li > 0
            LRo{end+1}=rRole{li}; Lws(end+1)=ws(li); Lwe(end+1)=we(li); Lcy(end+1)=cyc(li); Lh(end+1)=hh(li); Lst(end+1)=ss(li); %#ok<AGROW>
        else
            LRo{end+1}=''; Lws(end+1)=NaN; Lwe(end+1)=NaN; Lcy(end+1)=NaN; Lh(end+1)=NaN; Lst(end+1)=NaN; %#ok<AGROW>
        end
        if ri > 0
            RRo{end+1}=rRole{ri}; Rws(end+1)=ws(ri); Rwe(end+1)=we(ri); Rcy(end+1)=cyc(ri); Rh(end+1)=hh(ri); Rst(end+1)=ss(ri); %#ok<AGROW>
        else
            RRo{end+1}=''; Rws(end+1)=NaN; Rwe(end+1)=NaN; Rcy(end+1)=NaN; Rh(end+1)=NaN; Rst(end+1)=NaN; %#ok<AGROW>
        end
    end
    Tlr = table(cT', LRo', Lws', Lwe', Lcy', round(Lh',4), round(Lst',4), ...
                     RRo', Rws', Rwe', Rcy', round(Rh',4), round(Rst',4), ...
        'VariableNames', {'Terrain', ...
            'Left_Role','Left_StartPkt','Left_EndPkt','Left_Cycle','Left_Height_m','Left_Stride_m', ...
            'Right_Role','Right_StartPkt','Right_EndPkt','Right_Cycle','Right_Height_m','Right_Stride_m'});
    writetable(Tlr, xls, 'Sheet', 'Left and Right');  nSheets = nSheets + 1;

    % --- 'Leading vs Trailing' sheet: crossings with both feet and a known lead ---
    pT={}; pLs={}; pLws=[]; pLwe=[]; pLc=[]; pLh=[]; pLst=[];
           pTs={}; pTws=[]; pTwe=[]; pTc=[]; pTh=[]; pTst=[];
    for p = 1:size(rows,1)
        li = rows(p,1);  ri = rows(p,2);
        if li == 0 || ri == 0, continue; end
        lead = crossingLead(logE, rTerr{li}, (ws(li)+we(li)+ws(ri)+we(ri))/4, tol);
        if lead == 'L', ld=li; tr=ri; elseif lead == 'R', ld=ri; tr=li; else, continue; end
        pT{end+1}=rTerr{li}; %#ok<AGROW>
        pLs{end+1}=rSide{ld}; pLws(end+1)=ws(ld); pLwe(end+1)=we(ld); pLc(end+1)=cyc(ld); pLh(end+1)=hh(ld); pLst(end+1)=ss(ld); %#ok<AGROW>
        pTs{end+1}=rSide{tr}; pTws(end+1)=ws(tr); pTwe(end+1)=we(tr); pTc(end+1)=cyc(tr); pTh(end+1)=hh(tr); pTst(end+1)=ss(tr); %#ok<AGROW>
    end
    if ~isempty(pT)
        Tp = table(pT', pLs', pLws', pLwe', pLc', round(pLh',4), round(pLst',4), ...
                   pTs', pTws', pTwe', pTc', round(pTh',4), round(pTst',4), ...
            'VariableNames', {'Terrain', ...
                'Leading_Side','Leading_StartPkt','Leading_EndPkt','Leading_Cycle','Leading_Height_m','Leading_Stride_m', ...
                'Trailing_Side','Trailing_StartPkt','Trailing_EndPkt','Trailing_Cycle','Trailing_Height_m','Trailing_Stride_m'});
        writetable(Tp, xls, 'Sheet', 'Leading vs Trailing');  nSheets = nSheets + 1;
    end
    % --- 'Level Walk' sheet: all level-walk windows (both feet) ---
    if ~isempty(lwSide)
        [~, ow] = sort(lwWs);
        Tlw = table(repmat({'Level_Walk'}, numel(lwSide), 1), lwSide(ow)', lwWs(ow)', lwWe(ow)', lwCyc(ow)', ...
                    lwDs(ow)', lwDe(ow)', round(lwCts(ow)',4), round(lwCte(ow)',4), round(lwHh(ow)',4), round(lwSs(ow)',4), ...
            'VariableNames', {'Terrain','Side','Win_StartPkt','Win_EndPkt','Cycle', ...
                              'Cyc_StartPkt','Cyc_EndPkt','CycStart_s','CycEnd_s','Height_m','StrideLen_m'});
        writetable(Tlw, xls, 'Sheet', 'Level Walk');  nSheets = nSheets + 1;
    end
    fprintf('Exported window features (%d sheets: Left and Right / Leading vs Trailing / Level Walk) to:\n  %s\n', nSheets, xls);
end

function lead = crossingLead(logE, terrFull, ctrPkt, tol)
% Leading side ('L'/'R'/'U') of the nearest same-terrain log crossing within
% tol packets; '' if none.
    lead = '';  best = inf;  bl = '';
    for i = 1:numel(logE)
        if ~strcmp(logE(i).terr, terrFull), continue; end
        if ctrPkt >= logE(i).s && ctrPkt <= logE(i).e, d = 0;
        else, d = min(abs(ctrPkt - logE(i).s), abs(ctrPkt - logE(i).e)); end
        if d < best, best = d; bl = logE(i).lead; end
    end
    if isempty(bl) || best > tol, return; end
    lead = bl;
end

function c = cycleForCrossing(Feat, footLabel, Data, iDot, zvp, terrFull, ctr, pmod)
% Step-4 cycle number for a given crossing on one foot: the obstacle window of
% that foot/terrain nearest the crossing centre, mapped to its best cycle.
    c = NaN;
    if isempty(iDot) || numel(zvp) < 2, return; end
    k = find(strcmp({Feat.label}, footLabel), 1);  if isempty(k), return; end
    best = inf; bw = 0;
    for w = 1:numel(Feat(k).terrain)
        if ~strcmp(Feat(k).terrain{w}, terrFull), continue; end
        d = abs((Feat(k).startPkt(w)+Feat(k).endPkt(w))/2 - ctr);
        if d < best, best = d; bw = w; end
    end
    if bw == 0, return; end
    [cycS, cycE] = cyclePackets(zvp, Data.imu(iDot).packet, pmod);
    c = bestCycle(cycS, cycE, mod(Feat(k).startPkt(bw),pmod), mod(Feat(k).endPkt(bw),pmod));
end

function drawDecision(figDec, q, ntot, entry, lc, rc, vL, vY, pctv)
% Highlight the two candidate cycles (Left vs Right) of the Unknown crossing so
% the operator can decide which limb leads. Faded grey = all other cycles.
    pairs = {'Joint: hip_flexion_l',    'Joint: hip_flexion_r',    'Hip flexion (deg)'; ...
             'IMU: Left Thigh (Dot) X', 'IMU: Right Thigh (Dot) X','Thigh (Dot) X (deg)'};
    figure(figDec); clf(figDec);
    for p = 1:size(pairs,1)
        Li = find(strcmp(vL, pairs{p,1}), 1);  Ri = find(strcmp(vL, pairs{p,2}), 1);
        ax = subplot(1, size(pairs,1), p);  hold(ax,'on'); grid(ax,'on'); box(ax,'on');
        if ~isempty(Li), plot(ax, pctv, vY{Li}, 'Color',[0.86 0.86 0.86], 'LineWidth',0.5); end
        if ~isempty(Ri), plot(ax, pctv, vY{Ri}, 'Color',[0.86 0.86 0.86], 'LineWidth',0.5); end
        hs = []; leg = {};
        if ~isempty(Li) && ~isnan(lc) && lc>=1 && lc<=size(vY{Li},2)
            hs(end+1)=plot(ax, pctv, vY{Li}(:,lc), '-', 'Color',[0.00 0.45 0.85], 'LineWidth',3.2); %#ok<AGROW>
            leg{end+1}=sprintf('Left cycle %d', lc); %#ok<AGROW>
        end
        if ~isempty(Ri) && ~isnan(rc) && rc>=1 && rc<=size(vY{Ri},2)
            hs(end+1)=plot(ax, pctv, vY{Ri}(:,rc), '-', 'Color',[0.85 0.10 0.10], 'LineWidth',3.2); %#ok<AGROW>
            leg{end+1}=sprintf('Right cycle %d', rc); %#ok<AGROW>
        end
        xlabel(ax,'Gait cycle (%)'); ylabel(ax, pairs{p,3}); xlim(ax,[0 100]);
        title(ax, pairs{p,3}, 'Interpreter','none'); ax.FontWeight='bold';
        if ~isempty(hs), legend(ax, hs, leg, 'Location','best'); end
    end
    sgtitle(figDec, sprintf('Unknown %d/%d:  %s  (pkt %d-%d)  -  which leg leads?', ...
            q, ntot, entry.terr, entry.s, entry.e), 'Interpreter','none', 'FontWeight','bold');
end

function a = askLead(q, ntot, entry, lc, rc)
% Prompt the operator to classify one Unknown crossing as Left- or Right-leading.
    fprintf('\n  Unknown crossing %d/%d:  terrain %s,  packets %d-%d\n', q, ntot, entry.terr, entry.s, entry.e);
    fprintf('     Left  Foot cycle # = %s\n', num2str(lc));
    fprintf('     Right Foot cycle # = %s\n', num2str(rc));
    while true
        r = lower(strtrim(input('     Which leg is LEADING here?  [l]eft / [r]ight: ', 's')));
        if     ~isempty(r) && r(1)=='l', a = 'L'; return;
        elseif ~isempty(r) && r(1)=='r', a = 'R'; return;
        else,  fprintf('     Please type l or r.\n'); end
    end
end

%% ----- generic stride viewer (groups = side or leading/trailing) -----
function hF = buildGroupViewer(titleStr, sigs, defOn, fontName, figDir, tn, uTerr, canon, grpOrder, pngTag, grpToggle, allToggle, colorBy, xlab, xmax, ylab, compact)
    if nargin < 11, grpToggle = true;  end
    if nargin < 12, allToggle = false; end
    if nargin < 13, colorBy   = 'terrain'; end   % 'terrain' (Fig 2) or 'group' (Fig 3)
    if nargin < 14, xlab = 'Gait cycle (%)'; end
    if nargin < 15, xmax = 100; end
    if nargin < 16 || isempty(ylab), ylab = 'Angle (deg)'; end
    if nargin < 17 || isempty(compact), compact = false; end
    n = numel(sigs);
    pal = [0.00 0.00 0.00;   % Level_Walk     black
           0.85 0.33 0.10;   % Height1_Depth1 orange
           0.47 0.67 0.19;   % Height2_Depth1 green
           0.49 0.18 0.56;   % Height3_Depth1 purple
           0.00 0.50 0.50;   % Height1_Depth2 teal
           0.64 0.08 0.18;   % Height2_Depth2 dark red
           0.00 0.45 0.74;   % Height3_Depth2 blue
           0.93 0.69 0.13];  % spare          gold
    tcmap = pal(mod(0:max(numel(canon),1)-1, size(pal,1)) + 1, :);

    hF = figure('Color','w','Name',titleStr,'Position',[90 90 1400 800]);
    % Layout: 'compact' (trajectory viewers, few signals) narrows the control column
    % and shrinks the near-empty Signals panel so the plot gets much more width.
    % Axes left edge is kept well clear of the control column (LX+LW) so the y-tick
    % labels and the y-axis label are never hidden behind the terrain/signal boxes.
    if compact
        LX = 0.012;  LW = 0.205;  axPos = [0.30 0.12 0.665 0.79];
    else
        LX = 0.015;  LW = 0.30;   axPos = [0.40 0.10 0.565 0.82];
    end
    bw = LW*0.30;  bgap = LW*0.335;  lblW = LW*0.32;  ddw = LW - bgap - 0.005;
    if compact, sigH = max(0.10, min(0.53, 0.05*n + 0.06));  pnlY = 0.555 - sigH;
    else,       sigH = 0.53;  pnlY = 0.03;  end
    ax = axes(hF,'Position',axPos);
    uicontrol(hF,'Style','text','Units','normalized','Position',[LX 0.95 lblW 0.03], ...
        'String','Display:','BackgroundColor','w','FontName',fontName,'FontWeight','bold','HorizontalAlignment','left');
    dispItems = {'All strides','Mean +/- SD'};
    dispDD = uicontrol(hF,'Style','popupmenu','Units','normalized','Position',[LX+lblW 0.952 ddw 0.03], ...
        'String',dispItems,'Value',1,'FontName',fontName,'Callback',@(~,~) updateGroupViewer(hF));
    uicontrol(hF,'Style','pushbutton','Units','normalized','Position',[LX 0.908 bw 0.032], ...
        'String','Select all','FontName',fontName,'Callback',@(~,~) setAllG(hF,true));
    uicontrol(hF,'Style','pushbutton','Units','normalized','Position',[LX+bgap 0.908 bw 0.032], ...
        'String','Clear all','FontName',fontName,'Callback',@(~,~) setAllG(hF,false));
    uicontrol(hF,'Style','pushbutton','Units','normalized','Position',[LX+2*bgap 0.908 bw 0.032], ...
        'String','Save PNG','FontName',fontName,'Callback',@(~,~) savePNGg(hF));
    numCb = uicontrol(hF,'Style','checkbox','Units','normalized','Position',[LX 0.882 LW 0.022], ...
        'String','Show cycle numbers (= Excel ''Cycle'')','Value',0,'BackgroundColor','w', ...
        'FontName',fontName,'FontWeight','bold','Callback',@(~,~) updateGroupViewer(hF));
    % per-group show/hide toggles (Leading / Trailing / Unknown). Omitted for the
    % Left/Right viewer (side is chosen from the signal list). 'Unknown' starts
    % OFF; an 'All' toggle (when enabled) shows every cycle incl. Level_Walk.
    grpCb = gobjects(0,1);  allCb = gobjects(0,1);
    if grpToggle
        if strcmp(colorBy,'group')
            enc = 'colour = terrain (Leading dark / Trailing light),  line style = role';
        else
            sstyles = {'solid','dashed','dotted'};
            enc = sprintf('%s=%s', grpOrder{1}, sstyles{1});
            for gi = 2:numel(grpOrder), enc = [enc sprintf(',  %s=%s', grpOrder{gi}, sstyles{min(gi,3)})]; end %#ok<AGROW>
            if allToggle, enc = [enc ',  Level Walk=solid']; end
        end
        uicontrol(hF,'Style','text','Units','normalized','Position',[LX 0.860 LW 0.018], ...
            'String',enc,'BackgroundColor','w','FontName',fontName,'FontSize',8,'HorizontalAlignment','left');
        ng = numel(grpOrder);  nBtn = ng + double(allToggle);  gw = min(0.145, LW/nBtn);
        grpCb = gobjects(ng,1);
        for gi = 1:ng
            grpCb(gi) = uicontrol(hF,'Style','checkbox','Units','normalized', ...
                'Position',[LX+(gi-1)*gw 0.834 gw 0.022], 'String',grpOrder{gi}, ...
                'Value',double(~strcmpi(grpOrder{gi},'Unknown')), ...
                'BackgroundColor','w','FontName',fontName,'FontWeight','bold','FontSize',8, ...
                'Callback',@(~,~) updateGroupViewer(hF));
        end
        if allToggle
            allCb = uicontrol(hF,'Style','checkbox','Units','normalized', ...
                'Position',[LX+ng*gw 0.834 gw 0.022], 'String','Level Walk', 'Value',0, ...
                'BackgroundColor','w','FontName',fontName,'FontWeight','bold','FontSize',8, ...
                'Callback',@(~,~) updateGroupViewer(hF));
        end
    end

    tpnl = uipanel(hF,'Title','Terrain (none = all)','Units','normalized', ...
        'Position',[LX 0.565 LW 0.255],'BackgroundColor','w','FontName',fontName,'FontSize',9,'FontWeight','bold'); %#ok<*NASGU>

    nT = numel(uTerr); trh = 1/max(nT,1); terrCb = gobjects(nT,1);
    for k = 1:nT
        terrCb(k) = uicontrol(tpnl,'Style','checkbox','Units','normalized', ...
            'Position',[0.04 1-k*trh 0.94 trh*0.9], 'String',uTerr{k}, 'Value',0, ...
            'BackgroundColor','w','FontName',fontName,'FontSize',9,'Callback',@(~,~) updateGroupViewer(hF));
    end

    pnl = uipanel(hF,'Title','Signals','Units','normalized','Position',[LX pnlY LW sigH], ...
        'BackgroundColor','w','FontName',fontName,'FontSize',10,'FontWeight','bold');
    rh = 1/max(n,1); cb = gobjects(n,1);
    for k = 1:n
        cb(k) = uicontrol(pnl,'Style','checkbox','Units','normalized', ...
            'Position',[0.03 1-k*rh 0.95 rh*0.92], 'String',sigs(k).label, ...
            'Value',any(strcmp(sigs(k).label,defOn)), 'BackgroundColor','w', ...
            'FontName',fontName,'FontSize',9,'Callback',@(~,~) updateGroupViewer(hF));
    end
    S = struct('ax',ax,'cb',cb,'sigs',{sigs},'dispDD',dispDD,'dispItems',{dispItems}, ...
               'titleStr',titleStr,'fontName',fontName,'figDir',figDir,'tn',tn,'n',n, ...
               'terrCb',terrCb,'numCb',numCb,'canon',{canon},'tcmap',tcmap, ...
               'grpOrder',{grpOrder},'grpCb',grpCb,'allCb',allCb,'pngTag',pngTag,'colorBy',colorBy, ...
               'xlab',xlab,'xmax',xmax,'ylab',ylab);
    guidata(hF, S);  updateGroupViewer(hF);
end

function updateGroupViewer(hF)
    S = guidata(hF); ax = S.ax;
    meanMode = strcmp(S.dispItems{S.dispDD.Value}, 'Mean +/- SD');
    showNum  = (S.numCb.Value == 1) && ~meanMode;
    sel = {};
    for k = 1:numel(S.terrCb)
        if S.terrCb(k).Value == 1, sel{end+1} = S.terrCb(k).String; end %#ok<AGROW>
    end
    chk = []; for k = 1:S.n, if S.cb(k).Value == 1, chk(end+1) = k; end; end %#ok<AGROW>
    useGrp = ~isempty(S.grpCb);                         % group toggles present?
    cla(ax); hold(ax,'on'); legH = []; legN = {}; seen = {};  xmaxData = 0;
    for kk = 1:numel(chk)
        sg = S.sigs(chk(kk));
        x = sg.x; Y = sg.Y; terrCols = sg.terr; grpCols = sg.grp; cyc = sg.cyc;
        if isempty(sel), tKeep = true(1,numel(terrCols)); else, tKeep = ismember(terrCols, sel); end

        % Build the list of groups to draw - each toggle is INDEPENDENT and
        % ADDITIVE. Role groups (Leading/Trailing/Unknown) draw their own cycles;
        % 'All' adds the cycles that have a terrain label but no role (Level_Walk
        % and any labelled-but-unmatched), so it never double-plots the others.
        grpMask = {}; grpStyleIdx = []; grpLbl = {};
        for gi = 1:numel(S.grpOrder)
            on = ~useGrp || (S.grpCb(gi).Value == 1);
            if ~on, continue; end
            grpMask{end+1}     = tKeep & strcmp(grpCols, S.grpOrder{gi}); %#ok<AGROW>
            grpStyleIdx(end+1) = gi;                                      %#ok<AGROW>
            grpLbl{end+1}      = S.grpOrder{gi};                          %#ok<AGROW>
        end
        if ~isempty(S.allCb) && S.allCb.Value == 1
            grpMask{end+1}     = strcmp(terrCols, 'Level_Walk');  % Level_Walk cycles (own toggle, ignores terrain list)
            grpStyleIdx(end+1) = 1;          % solid / full                 %#ok<AGROW>
            grpLbl{end+1}      = 'Level Walk';                              %#ok<AGROW>
        end

        for gg = 1:numel(grpMask)
            colsG = grpMask{gg};  gi = grpStyleIdx(gg);
            if ~any(colsG), continue; end
            uterr = unique(terrCols(colsG));
            for ui = 1:numel(uterr)
                ter = uterr{ui};
                cc = colsG & strcmp(terrCols, ter);
                Yt = Y(:, cc);
                if isempty(ter), tname = '(unlabelled)'; else, tname = ter; end
                if strcmp(S.colorBy, 'group')
                    % colour = terrain hue, Leading=dark / Trailing=light shade;
                    % line style = role. Distinguishes BOTH terrain and role.
                    col = comboColor(grpLbl{gg}, ter, S);  st = roleStyle(grpLbl{gg});
                else
                    % colour = terrain (hue), style/shade = group (side)
                    if isempty(ter), basec = [0.55 0.55 0.55]; else, basec = terrColor(ter, S); end
                    if gi == 1,     col = basec;       st = '-';
                    elseif gi == 2, col = basec*0.6;   st = '--';
                    else,           col = basec*0.45;  st = ':'; end
                end
                h = plotStride(ax, x, Yt, col, st, meanMode);
                if showNum, annotateCycles(ax, x, Yt, cyc(cc), col); end
                rlast = find(any(isfinite(Yt),2), 1, 'last');           % extent of shown data
                if ~isempty(rlast), xmaxData = max(xmaxData, x(rlast)); end
                [legH,legN,seen] = addLeg(legH,legN,seen, h, sprintf('%s | %s | %s', sg.label, grpLbl{gg}, tname));
            end
        end
    end
    hold(ax,'off'); grid(ax,'on'); box(ax,'on');
    ax.FontName = S.fontName; ax.FontSize = 12; ax.FontWeight = 'bold';
    xlabel(ax,S.xlab,'FontSize',15,'FontWeight','bold','FontName',S.fontName);
    ylabel(ax,S.ylab,'FontSize',15,'FontWeight','bold','FontName',S.fontName);
    title(ax,S.titleStr,'FontSize',16,'FontWeight','bold','FontName',S.fontName,'Interpreter','none');
    if xmaxData > 0, xlim(ax,[0 xmaxData]); else, xlim(ax,[0 S.xmax]); end   % fit x-axis to shown data
    if ~isempty(legH), legend(ax, legH, legN, 'Location','eastoutside','Interpreter','none','FontSize',9);
    else, legend(ax,'off'); end
end

function h = plotStride(ax, x, Y, col, st, meanMode)
    h = [];
    if isempty(Y) || all(isnan(Y(:))), return; end
    if meanMode
        mu = mean(Y,2,'omitnan'); sdv = std(Y,0,2,'omitnan'); g = ~isnan(mu) & ~isnan(sdv);
        if ~any(g), return; end
        fill(ax, [x(g); flipud(x(g))], [mu(g)+sdv(g); flipud(mu(g)-sdv(g))], col, 'FaceAlpha',0.12,'EdgeColor','none');
        h = plot(ax, x, mu, st, 'Color', col, 'LineWidth', 3.4);
    else
        hh = plot(ax, x, Y, st, 'Color', col, 'LineWidth', 2.0); h = hh(1);
    end
end

function [legH, legN, seen] = addLeg(legH, legN, seen, h, lbl)
    if isempty(h) || isempty(lbl) || any(strcmp(seen, lbl)), return; end
    legH(end+1) = h; legN{end+1} = lbl; seen{end+1} = lbl;
end

function annotateCycles(ax, x, Y, idx, col)
    for c = 1:size(Y,2)
        y = Y(:,c);
        [~, mi] = max(y);
        if isempty(mi) || isnan(y(mi)), continue; end
        text(ax, x(mi), y(mi), sprintf(' %d', idx(c)), 'Color', col*0.55, ...
            'FontSize', 8, 'FontWeight', 'bold', 'Clipping', 'on', ...
            'VerticalAlignment', 'bottom', 'HorizontalAlignment', 'center');
    end
end

function col = terrColor(ter, S)
    i = find(strcmp(S.canon, ter), 1);
    if isempty(i), col = [0.4 0.4 0.4]; else, col = S.tcmap(i,:); end
end

function c = comboColor(label, ter, S)
% Colour for the Leading/Trailing viewer: terrain sets the hue, role sets the
% shade (Leading = dark, Trailing = light) -> every terrain AND role is a
% distinct colour. Uses a tab20-style paired palette (dark/light per hue).
    tab20 = [0.12 0.47 0.71; 0.68 0.78 0.91;   % blue
             1.00 0.50 0.05; 1.00 0.73 0.47;   % orange
             0.17 0.63 0.17; 0.60 0.87 0.54;   % green
             0.84 0.15 0.16; 1.00 0.60 0.59;   % red
             0.58 0.40 0.74; 0.77 0.69 0.84;   % purple
             0.55 0.34 0.29; 0.77 0.61 0.58;   % brown
             0.89 0.47 0.76; 0.97 0.71 0.82;   % pink
             0.49 0.49 0.49; 0.78 0.78 0.78;   % gray
             0.74 0.74 0.13; 0.86 0.86 0.55;   % olive
             0.09 0.75 0.81; 0.62 0.85 0.90];  % cyan
    switch label
        case 'Unknown',    c = [0.45 0.45 0.45]; return;
        case 'Level Walk', c = [0.00 0.00 0.00]; return;
    end
    t = find(strcmp(S.canon, ter), 1);  if isempty(t), t = 1; end
    hue = mod(t-1, 10);
    if strcmp(label,'Trailing'), c = tab20(hue*2+2, :);   % light shade
    else,                        c = tab20(hue*2+1, :);   % dark shade (Leading)
    end
end

function st = roleStyle(label)
% Line style per role, reinforcing colour.
    switch label
        case 'Trailing', st = '--';
        case 'Unknown',  st = ':';
        otherwise,       st = '-';   % Leading / Level Walk
    end
end

function setAllG(hF, val)
    S = guidata(hF);
    for k = 1:S.n, S.cb(k).Value = val; end
    updateGroupViewer(hF);
end

function savePNGg(hF)
    S = guidata(hF);
    if ~exist(S.figDir,'dir'), mkdir(S.figDir); end
    fn = fullfile(S.figDir, sprintf('LinkedStrides_%s_Test%d.png', S.pngTag, S.tn));
    exportgraphics(hF, fn, 'Resolution', 300);
    fprintf('PNG saved: %s\n', fn);
end

