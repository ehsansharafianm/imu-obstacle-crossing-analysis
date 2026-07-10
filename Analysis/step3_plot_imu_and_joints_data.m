clc
clear all
close all
addpath(fileparts(mfilename('fullpath')));

%% ========================================================================
%% SUBJECT INPUT
%% ========================================================================
subj_raw = input('  Input Test Number: ', 's');
if isempty(subj_raw), subjectNumber = 2; else, subjectNumber = str2double(subj_raw); end

%% ========================================================================
%% APPEARANCE SETTINGS — ADJUST HERE
%% ========================================================================
FONT_NAME      = 'Arial';
TITLE_SIZE     = 18;
XLABEL_SIZE    = 15;
YLABEL_SIZE    = 15;
TICK_SIZE      = 12;
LEGEND_SIZE    = 10;
BOX_LINE_WIDTH = 1.3;
GRID_ON        = true;
FIGURE_POS     = [60, 60, 1320, 760];

PLOT_STYLE     = 'Line';     % initial style: 'Line' | 'Scatter' | 'Both'
LINE_WIDTH     = 1.6;        % line width (all lines solid)
SCATTER_SIZE   = 14;         % dot size

LEGEND_ON      = true;
START_ALL_ON   = false;      % if true, every IMU ticked; otherwise use DEFAULT_ON
DEFAULT_ON     = {'Left Foot (Awinda)', 'Left Foot (Dot)'};  % IMUs ticked on first open
DEFAULT_ANGLES = [false true false];   % [Z X Y] shown on first open (X only)

% Unwrap removes the +/-180 deg jumps from atan2 so a sensor crossing the
% wrap boundary shows continuous motion instead of full-scale noise.
UNWRAP_ANGLES  = false;

% Offset removal: subtract the mean of the first OFFSET_SAMPLES samples from
% each trace/angle so every curve starts at ~0 degrees.
REMOVE_OFFSET  = true;
OFFSET_SAMPLES = 10;

% Streaming Dot IMUs (1-4) may carry a large packet-counter offset (a multiple
% of 1e6) that encodes the terrain/condition. Strip it with mod so their
% packet counters line up with the recording IMUs (5,6). Set 0 to disable.
PACKET_MODULUS = 1e6;

ANGLE_MARKERS  = {'o','s','^'};   % markers for [Z X Y] when >1 angle is shown

CB_COLUMNS     = 1;
CB_FONT_SIZE   = 11;
CB_TEXT_COLOR  = [0 0 0];

RATE_AWINDA = 40;            % Hz (native)
RATE_DOT    = 60;            % Hz (native)

% Resample every IMU onto one uniform rate so the systems share a time base:
% Awinda (40 Hz) is upsampled to match Dot (60 Hz); Dot is put on the same
% grid (also fixes dropped-packet gaps). Set TARGET_RATE = 0 to keep native.
TARGET_RATE     = 60;
RESAMPLE_METHOD = 'linear';  % interp1 method: 'linear' | 'spline' | 'pchip'

% Sync: align Awinda & Dot using the first foot-lift peak in the X angle.
% The peak sign is auto-detected, so oppositely-mounted sensors still match.
SYNC_ENABLE      = true;
PEAK_MIN_DEG     = 20;       % a lift peak must reach at least this magnitude
SHOW_SYNC_FIGURE = true;     % before/after sanity-check figure

EXPORT_RESOLUTION = 300;

%% ========================================================================
%% SYSTEM / SENSOR DEFINITIONS
%% ========================================================================
subjFolder = ['Test ' num2str(subjectNumber)];
bodyOrder = {'Left Foot','Right Foot','Left Thigh','Right Thigh', ...
             'Left Shank','Right Shank','Pelvis','Sternum', ...
             'Left Upper Arm','Right Upper Arm','Left Forearm','Right Forearm'};

systems(1).name='Awinda'; systems(1).folder='Awinda IMUs'; systems(1).rate=RATE_AWINDA; systems(1).ext='txt'; systems(1).euler='ZXY';
systems(1).defs = { '00B4AB26','Sternum'; '00B4AB22','Pelvis'; ...
                    '00B4AB23','Left Foot'; '00B4AB29','Right Foot'; ...
                    '00B4AB2D','Left Thigh'; '00B4AB2B','Right Thigh'; ...
                    '00B4AB25','Left Shank'; '00B4AB27','Right Shank'; ...
                    '00B4AB2E','Left Upper Arm'; '00B4AB31','Right Upper Arm'; ...
                    '00B4AB28','Left Forearm';   '00B4AB2F','Right Forearm' };

systems(2).name='Dot'; systems(2).folder='Dot IMUs'; systems(2).rate=RATE_DOT; systems(2).ext='csv'; systems(2).euler='ZYX';
systems(2).defs = { 'IMU1','Left Foot'; 'IMU2','Right Foot'; ...
                    'IMU3','Left Thigh'; 'IMU4','Right Thigh'; ...
                    'IMU5','Left Shank'; 'IMU6','Right Shank' };

%% ========================================================================
%% DOT SYNC: find the common packet-counter window across all Dot IMUs
%% ========================================================================
% Streaming IMUs (1-4) start mid-stream; recording IMUs (5,6) start at packet
% 0. Crop every Dot IMU to the overlapping packet range so they align in time.
dotDir = fullfile('..','Data','Dot IMUs', subjFolder);
dotStart = -inf; dotEnd = inf;
if isfolder(dotDir)
    for r = 1:size(systems(2).defs,1)
        fp = findFile(dotDir, [systems(2).defs{r,1} '_*.csv']);
        if isempty(fp), continue; end
        [c0, M0] = readIMUFile(fp);
        pkt0 = M0(:, find(strcmpi(c0,'PacketCounter'),1));
        if PACKET_MODULUS > 0, pkt0 = mod(pkt0, PACKET_MODULUS); end
        dotStart = max(dotStart, min(pkt0));
        dotEnd   = min(dotEnd,   max(pkt0));
    end
    fprintf('Dot common packet window: [%g, %g]\n', dotStart, dotEnd);
end

%% ========================================================================
%% READ BOTH SYSTEMS -> Euler angles (ZXY), offset removed
%% ========================================================================
labels={}; tCell={}; eCell={}; xCell={}; xNamesCell={}; qCell={};
for b = 1:numel(bodyOrder)
    body = bodyOrder{b};
    for sIdx = 1:numel(systems)
        S0 = systems(sIdx);
        dataDir = fullfile('..','Data', S0.folder, subjFolder);
        if ~isfolder(dataDir), continue; end
        row = find(strcmp(S0.defs(:,2), body), 1);
        if isempty(row), continue; end
        key = S0.defs{row,1};
        if strcmp(S0.ext,'csv'), pat = [key '_*.csv']; else, pat = ['*' key '*.txt']; end
        fp = findFile(dataDir, pat);
        if isempty(fp), warning('%s %s: file not found (%s).', S0.name, body, pat); continue; end
        [cols, M] = readIMUFile(fp);
        pkt = M(:, find(strcmpi(cols,'PacketCounter'),1));
        if strcmp(S0.name,'Dot')
            if PACKET_MODULUS > 0, pkt = mod(pkt, PACKET_MODULUS); end  % strip terrain offset
            m = pkt >= dotStart & pkt <= dotEnd;      % crop to the common window
            M = M(m,:); pkt = pkt(m);
            t = (pkt - dotStart) / S0.rate;           % shared zero across Dot IMUs
        else
            pkt = unwrapCounter(pkt, 65536);          % undo Awinda 16-bit PacketCounter rollover
            t = (pkt - pkt(1)) / S0.rate;             % time from this device's packets
        end
        Q = contigQuat(getQuatCols(cols, M));            % raw quaternion [w x y z], sign-continuous
        E = quatEuler(Q, S0.euler);                      % [Z X Y] deg (per-system sequence)
        if UNWRAP_ANGLES
            E = rad2deg(unwrap(deg2rad(E)));          % remove +/-180 deg jumps
        end
        % Extra raw channels to carry through: packet (offset-removed), acc, gyro.
        xN = {'Packet'};  X = pkt(:);
        for nm = {'Acc_X','Acc_Y','Acc_Z','Gyr_X','Gyr_Y','Gyr_Z'}
            j = find(strcmpi(cols, nm{1}), 1);
            if ~isempty(j), X = [X, M(:,j)]; xN{end+1} = nm{1}; end %#ok<AGROW>
        end
        if TARGET_RATE > 0 && numel(t) > 1
            tu = (t(1):1/TARGET_RATE:t(end))';        % uniform target-rate grid
            E  = interp1(t, E, tu, RESAMPLE_METHOD);  % upsample/resample onto it
            X  = interp1(t, X, tu, RESAMPLE_METHOD);  % carry acc/gyro/packet along
            Q  = interp1(t, Q, tu, RESAMPLE_METHOD);  % quaternion too (renormalized below)
            Q  = Q ./ vecnorm(Q, 2, 2);
            t  = tu;
        end
        if REMOVE_OFFSET
            k = min(OFFSET_SAMPLES, size(E,1));
            E = E - mean(E(1:k,:), 1);                % zero each angle at the start
        end
        labels{end+1} = sprintf('%s (%s)', body, S0.name); %#ok<AGROW>
        tCell{end+1}  = t;                                  %#ok<AGROW>
        eCell{end+1}  = E;                                  %#ok<AGROW>
        xCell{end+1}  = X;                                  %#ok<AGROW>
        qCell{end+1}  = Q;                                  %#ok<AGROW>
        xNamesCell{end+1} = xN;                             %#ok<AGROW>
        fprintf('  %-22s <- %s  (%d frames)\n', labels{end}, key, size(M,1));
    end
end
nItem = numel(labels);
if nItem == 0, error('No IMU files found for %s under Data/.', subjFolder); end

% Flip (negate) selected Awinda channels for sign consistency. This carries
% through to the step-3 figures, the Excel export and the saved Data struct.
flipChannels = {'Right Thigh (Awinda)', 'Right Shank (Awinda)'};
for i = 1:nItem
    if any(strcmp(labels{i}, flipChannels))
        eCell{i} = -eCell{i};
    end
end

% Report the length of every channel after upsampling/resampling.
fprintf('\n--- Data length after upsampling (target %g Hz) ---\n', TARGET_RATE);
lensAll = zeros(1, nItem);
for i = 1:nItem
    lensAll(i) = size(eCell{i}, 1);
    fprintf('  %-22s %6d samples   %.3f s\n', labels{i}, lensAll(i), tCell{i}(end));
end
if numel(unique(lensAll)) == 1
    fprintf('  All channels equal length: %d samples.\n', lensAll(1));
else
    fprintf('  NOTE: lengths differ (min=%d, max=%d).\n', min(lensAll), max(lensAll));
end

%% ========================================================================
%% SYNC: align Awinda & Dot by the first Left-foot lift peak in X
%% ========================================================================
COL_X = 2;   % E columns are [Z X Y]
if SYNC_ENABLE
    [tLA,vLA] = footPeak(labels,tCell,eCell,'Left Foot (Awinda)',  COL_X, PEAK_MIN_DEG);
    [tLD,vLD] = footPeak(labels,tCell,eCell,'Left Foot (Dot)',     COL_X, PEAK_MIN_DEG);
    [tRA,~  ] = footPeak(labels,tCell,eCell,'Right Foot (Awinda)', COL_X, PEAK_MIN_DEG);
    [tRD,~  ] = footPeak(labels,tCell,eCell,'Right Foot (Dot)',    COL_X, PEAK_MIN_DEG);
    fprintf('\n--- Sync: first X peak >= %g deg (sign auto-detected) ---\n', PEAK_MIN_DEG);
    fprintf('  Left  foot:  Awinda=%.3f s,  Dot=%.3f s  ->  delay = %.3f s\n', tLA, tLD, tLA-tLD);
    fprintf('  Right foot:  Awinda=%.3f s,  Dot=%.3f s  ->  delay = %.3f s\n', tRA, tRD, tRA-tRD);

    % Keep the BEFORE-sync left-foot traces for the sanity figure.
    iLA = find(strcmp(labels,'Left Foot (Awinda)'),1);
    iLD = find(strcmp(labels,'Left Foot (Dot)'),1);
    preA_t=tCell{iLA}; preA_x=eCell{iLA}(:,COL_X);
    preD_t=tCell{iLD}; preD_x=eCell{iLD}(:,COL_X);

    if ~isnan(tLA) && ~isnan(tLD)
        % Align Awinda's left-foot peak to Dot's, then keep ONLY the span both
        % systems cover (drop the early part of the longer Dot). Re-zero time
        % so t = 0 at the start of that overlap (= when Awinda starts here).
        shiftAw = tLD - tLA;                          % Awinda (& joints) shift
        alStart = -inf; alEnd = inf;                  % overlap in the aligned frame
        for i = 1:nItem
            ti = tCell{i}; if endsWith(labels{i},'(Awinda)'), ti = ti + shiftAw; end
            alStart = max(alStart, ti(1));
            alEnd   = min(alEnd,   ti(end));
        end
        tgAligned = (alStart : 1/TARGET_RATE : alEnd)';   % overlap grid (aligned frame)
        tg = tgAligned - tgAligned(1);                    % re-zeroed: t=0 at window start
        for i = 1:nItem
            ti = tCell{i}; if endsWith(labels{i},'(Awinda)'), ti = ti + shiftAw; end
            eCell{i} = interp1(ti, eCell{i}, tgAligned, RESAMPLE_METHOD);
            xCell{i} = interp1(ti, xCell{i}, tgAligned, RESAMPLE_METHOD);
            qCell{i} = interp1(ti, qCell{i}, tgAligned, RESAMPLE_METHOD);
            qCell{i} = qCell{i} ./ vecnorm(qCell{i}, 2, 2);
            tCell{i} = tg;
        end
        fprintf('  Dot=reference. Awinda shifted %+.3f s; cropped to overlap [%.3f, %.3f] s -> %d samples each (t=0 at start).\n', ...
                shiftAw, alStart, alEnd, numel(tg));
    else
        shiftAw = NaN; tgAligned = [];
        warning('Left-foot X peak not found in a system - sync skipped.');
    end

    if SHOW_SYNC_FIGURE
        delaySec  = tLA - tLD;                       % left-foot delay (Awinda - Dot)
        delaySamp = round(abs(delaySec) * TARGET_RATE);
        hSync = figure('Color','w','Name','Sync check - Left Foot X','Position',[120 120 1000 760]);
        subplot(2,1,1); hold on; grid on; box on;
        plot(preA_t, preA_x, '-', 'LineWidth', 1.6);
        plot(preD_t, preD_x, '-', 'LineWidth', 1.6);
        if ~isnan(tLA), plot(tLA, vLA, 'k^', 'MarkerFaceColor','y', 'MarkerSize',10); end
        if ~isnan(tLD), plot(tLD, vLD, 'kv', 'MarkerFaceColor','y', 'MarkerSize',10); end
        title('Before sync - Left Foot X  (markers = detected first peak)');
        xlabel('Time (s)'); ylabel('X (deg)');
        legend({'Awinda','Dot','Awinda peak','Dot peak'}, 'Location','best');
        subplot(2,1,2); hold on; grid on; box on;
        plot(tCell{iLA}, eCell{iLA}(:,COL_X), '-', 'LineWidth', 1.6);
        plot(tCell{iLD}, eCell{iLD}(:,COL_X), '-', 'LineWidth', 1.6);
        if ~isempty(tgAligned), xline(tLD - tgAligned(1), 'k--'); end
        title('After sync - cropped to overlap (t = 0 at window start)');
        xlabel('Time (s)'); ylabel('X (deg)'); legend({'Awinda','Dot'}, 'Location','best');
        sgtitle(hSync, sprintf('Left-foot delay (Awinda - Dot) = %+.3f s   (length = %d samples @ %g Hz)', ...
                delaySec, delaySamp, TARGET_RATE), 'FontWeight','bold','FontSize',13);
    end
end

%% ========================================================================
%% JOINT ANGLES (OpenSim IK, Awinda) -> apply Awinda delay + upsample to 60 Hz
%% ========================================================================
jLabels = {}; jU = [];
ikDir = fullfile('..','Results','OpenSim Outputs', subjFolder, 'IKResults');
mots  = dir(fullfile(ikDir, 'ik_*.mot'));
if isempty(mots)
    warning('No IK .mot in %s - joint angles skipped (run step 1 first).', ikDir);
elseif ~SYNC_ENABLE || ~exist('tg','var')
    warning('Sync grid not available - joint angles skipped.');
else
    [~,nw] = max([mots.datenum]);
    motFile = fullfile(ikDir, mots(nw).name);
    [jt, jData, jLabels] = readMot(motFile);          % jt in s, jData N x nJoint
    % Keep lower-limb (ankle / knee / hip) AND upper-limb (shoulder / elbow)
    % coordinates. Drop knee beta, hip rotation, and shoulder rotation (arm_rot) -
    % rotation about the long axis is the least reliable DOF from a single IMU, so
    % it is excluded here just like hip_rotation. Add 'arm_rot' back to keep it.
    keepJ = (contains(jLabels,'hip') | contains(jLabels,'knee_angle') | ...
             contains(jLabels,'ankle_angle') | contains(jLabels,'arm_flex') | ...
             contains(jLabels,'arm_add') | contains(jLabels,'elbow_flex')) ...
             & ~contains(jLabels,'beta') & ~contains(jLabels,'hip_rotation');
    jLabels = jLabels(keepJ);  jData = jData(:, keepJ);
    nBefore = numel(jt);
    fsJ = 1/median(diff(jt));
    fprintf('\n--- Joint angles: %s ---\n', mots(nw).name);
    fprintf('  Before upsample : %d samples @ %.0f Hz  (%.2f s)\n', nBefore, fsJ, jt(end)-jt(1));
    jt = jt + shiftAw;                                 % align to Dot (aligned frame)
    fprintf('  Delay applied   : %+.3f s  (shift to align with Dot)\n', shiftAw);
    inWin = jt >= tgAligned(1) & jt <= tgAligned(end);
    fprintf('  After cut       : %d samples within overlap [%.3f, %.3f] s\n', nnz(inWin), tgAligned(1), tgAligned(end));
    jU = interp1(jt, jData, tgAligned, RESAMPLE_METHOD);  % onto the overlap 60 Hz grid
    fprintf('  After upsample  : %d samples @ %g Hz\n', numel(tgAligned), TARGET_RATE);
end

% Unique colour per IMU trace (system distinguished by colour now that all
% lines are solid).
if exist('turbo','file'), colorMat = turbo(nItem); else, colorMat = hsv(nItem); end

angFull  = {'Euler Z (deg)','Euler X (deg)','Euler Y (deg)'};
angShort = {'Z','X','Y'};
titleStr = sprintf('Awinda + Dot   |   Test %d', subjectNumber);

%% ========================================================================
%% BUILD FIGURE
%% ========================================================================
hFig = figure('Position', FIGURE_POS, 'Color', 'w', 'Name', titleStr);
ax = axes(hFig, 'Position', [0.42 0.13 0.55 0.76]);

LX = 0.02;  LW = 0.34;

% --- Angle multi-select (Z / X / Y) ---
uicontrol(hFig,'Style','text','Units','normalized','Position',[LX 0.95 0.09 0.03], ...
    'String','Angles:','BackgroundColor','w','FontName',FONT_NAME,'FontSize',11, ...
    'FontWeight','bold','HorizontalAlignment','left');
angCb = gobjects(3,1);
for a = 1:3
    angCb(a) = uicontrol(hFig,'Style','checkbox','Units','normalized', ...
        'Position',[LX+0.10+(a-1)*0.075, 0.95, 0.07, 0.03], 'String',angShort{a}, ...
        'Value',DEFAULT_ANGLES(a),'BackgroundColor','w','FontName',FONT_NAME, ...
        'FontSize',11,'FontWeight','bold','Callback',@(~,~) updatePlot(hFig));
end

% --- Plot style ---
uicontrol(hFig,'Style','text','Units','normalized','Position',[LX 0.905 0.12 0.035], ...
    'String','Plot style:','BackgroundColor','w','FontName',FONT_NAME,'FontSize',11, ...
    'FontWeight','bold','HorizontalAlignment','left');
styleItems = {'Line','Scatter','Both'};
styleDD = uicontrol(hFig,'Style','popupmenu','Units','normalized', ...
    'Position',[LX+0.12 0.907 0.20 0.04],'String',styleItems, ...
    'Value',find(strcmpi(styleItems,PLOT_STYLE),1), ...
    'FontName',FONT_NAME,'FontSize',11,'Callback',@(~,~) updatePlot(hFig));

uicontrol(hFig,'Style','pushbutton','Units','normalized','Position',[LX 0.858 0.105 0.04], ...
    'String','Select all','FontName',FONT_NAME,'FontSize',10,'Callback',@(~,~) setAll(hFig,true));
uicontrol(hFig,'Style','pushbutton','Units','normalized','Position',[LX+0.115 0.858 0.105 0.04], ...
    'String','Clear all','FontName',FONT_NAME,'FontSize',10,'Callback',@(~,~) setAll(hFig,false));
uicontrol(hFig,'Style','pushbutton','Units','normalized','Position',[LX+0.23 0.858 0.105 0.04], ...
    'String','Save PNG','FontName',FONT_NAME,'FontSize',10,'Callback',@(~,~) savePNG(hFig));

% --- IMU toggles ---
pnl = uipanel(hFig,'Title','IMUs (body + system)','Units','normalized', ...
    'Position',[LX 0.04 LW 0.80],'BackgroundColor','w', ...
    'FontName',FONT_NAME,'FontSize',11,'FontWeight','bold');
nRows = ceil(nItem / CB_COLUMNS); cw = 1/CB_COLUMNS; chh = 1/nRows;
cb = gobjects(nItem,1);
for i = 1:nItem
    c = floor((i-1)/nRows); r = mod((i-1),nRows);
    initOn = START_ALL_ON || any(strcmp(labels{i}, DEFAULT_ON));
    cb(i) = uicontrol(pnl,'Style','checkbox','Units','normalized', ...
        'Position',[c*cw+0.02, 1-(r+1)*chh, cw-0.03, chh*0.85], ...
        'String',labels{i},'Value',initOn, ...
        'BackgroundColor','w','ForegroundColor',CB_TEXT_COLOR, ...
        'FontName',FONT_NAME,'FontSize',CB_FONT_SIZE,'Callback',@(~,~) updatePlot(hFig));
end

S = struct('ax',ax,'cb',cb,'angCb',angCb,'time',{tCell},'euler',{eCell}, ...
           'label',{labels},'color',colorMat,'n',nItem,'styleDD',styleDD, ...
           'styleItems',{styleItems},'angFull',{angFull},'angShort',{angShort}, ...
           'angMarkers',{ANGLE_MARKERS},'titleStr',titleStr,'LEGEND_ON',LEGEND_ON, ...
           'LEGEND_SIZE',LEGEND_SIZE,'FONT_NAME',FONT_NAME,'TITLE_SIZE',TITLE_SIZE, ...
           'XLABEL_SIZE',XLABEL_SIZE,'YLABEL_SIZE',YLABEL_SIZE,'TICK_SIZE',TICK_SIZE, ...
           'BOX_LINE_WIDTH',BOX_LINE_WIDTH,'GRID_ON',GRID_ON,'LINE_WIDTH',LINE_WIDTH, ...
           'SCATTER_SIZE',SCATTER_SIZE,'figDir',fullfile('..','Results','Parameters Output',subjFolder), ...
           'subjectNumber',subjectNumber,'EXPORT_RESOLUTION',EXPORT_RESOLUTION);
guidata(hFig, S);
updatePlot(hFig);

fprintf('Ready: %d IMU traces (Awinda + Dot) for Test %d.\n', nItem, subjectNumber);

%% ========================================================================
%% COMBINED FIGURE: all joint angles + IMU Euler data (synced, 60 Hz)
%% ========================================================================
if ~isempty(jU)
    angShort3 = {'Z','X','Y'};
    T={}; Y={}; L={};
    for i = 1:nItem
        for a = 1:3
            T{end+1}=tCell{i};                              %#ok<SAGROW>
            Y{end+1}=eCell{i}(:,a);                         %#ok<SAGROW>
            L{end+1}=sprintf('IMU: %s %s', labels{i}, angShort3{a}); %#ok<SAGROW>
        end
    end
    for j = 1:numel(jLabels)
        T{end+1}=tg;                                        %#ok<SAGROW>
        Y{end+1}=jU(:,j);                                   %#ok<SAGROW>
        L{end+1}=sprintf('Joint: %s', jLabels{j});          %#ok<SAGROW>
    end
    defOn = {'IMU: Left Foot (Awinda) X', 'IMU: Left Foot (Dot) X'};
    buildComboViewer(sprintf('Combined: joints + IMU  |  Test %d', subjectNumber), ...
        T, Y, L, defOn, FONT_NAME, fullfile('..','Results','Parameters Output',subjFolder), subjectNumber);
end

%% ========================================================================
%% FINAL SAMPLE-COUNT SUMMARY
%% ========================================================================
fprintf('\n=== Final sample counts (after sync + %g Hz resample) ===\n', TARGET_RATE);
iAw = find(cellfun(@(s) endsWith(s,'(Awinda)'), labels), 1);
iDt = find(cellfun(@(s) endsWith(s,'(Dot)'),    labels), 1);
if ~isempty(iAw), fprintf('  Awinda IMU    : %d samples\n', numel(tCell{iAw})); end
if ~isempty(iDt), fprintf('  Dot IMU       : %d samples\n', numel(tCell{iDt})); end
if ~isempty(jU),  fprintf('  Joint angles  : %d samples\n', size(jU,1));
else,             fprintf('  Joint angles  : (not loaded)\n'); end
fprintf('  (all share the same %g Hz time grid, so these should match)\n', TARGET_RATE);

%% ========================================================================
%% EXPORT TO A MULTI-SHEET EXCEL WORKBOOK (synced, 60 Hz)
%% ========================================================================
% Sheets group left+right per segment; columns are prefixed by side.
if exist('tg','var') && ~isempty(tg)
    outDir = fullfile('..','Results','Parameters Output', subjFolder);
    if ~exist(outDir,'dir'), mkdir(outDir); end
    xlsFile = fullfile(outDir, sprintf('AllData_Test%d.xlsx', subjectNumber));
    if exist(xlsFile,'file'), delete(xlsFile); end   % start fresh (no stale sheets)
    angShortE = {'Z','X','Y'};

    % {sheet name , {item label, column prefix} ... }
    sheetSpec = {
        'Dot IMUs Foot',                  {'Left Foot (Dot)','Left';    'Right Foot (Dot)','Right'};
        'Dot IMUs Thigh',                 {'Left Thigh (Dot)','Left';   'Right Thigh (Dot)','Right'};
        'Dot IMUs Shank',                 {'Left Shank (Dot)','Left';   'Right Shank (Dot)','Right'};
        'Awinda IMUs Foot',               {'Left Foot (Awinda)','Left'; 'Right Foot (Awinda)','Right'};
        'Awinda IMUs Thigh',              {'Left Thigh (Awinda)','Left';'Right Thigh (Awinda)','Right'};
        'Awinda IMUs Shank',              {'Left Shank (Awinda)','Left';'Right Shank (Awinda)','Right'};
        'Awinda IMUs Pelvis and Sternum', {'Pelvis (Awinda)','Pelvis';  'Sternum (Awinda)','Sternum'};
        'Awinda IMUs Arms',               {'Left Upper Arm (Awinda)','LeftUpperArm'; 'Right Upper Arm (Awinda)','RightUpperArm'; ...
                                           'Left Forearm (Awinda)','LeftForearm';    'Right Forearm (Awinda)','RightForearm'} };

    nSheets = 0;
    for sh = 1:size(sheetSpec,1)
        sheet = sheetSpec{sh,1};  members = sheetSpec{sh,2};
        vn = {'time_s'};  D = tg(:);  hasData = false;
        for m = 1:size(members,1)
            k = find(strcmp(labels, members{m,1}), 1);
            if isempty(k), continue; end
            hasData = true;  pre = members{m,2};
            pk = find(strcmp(xNamesCell{k},'Packet'), 1);
            if ~isempty(pk)                           % packet counter first
                vn{end+1} = sprintf('%s_Packet', pre); %#ok<SAGROW>
                D = [D, xCell{k}(:,pk)];               %#ok<AGROW>
            end
            for a = 1:3                               % then Euler angles
                vn{end+1} = sprintf('%s_Euler%s_deg', pre, angShortE{a}); %#ok<SAGROW>
                D = [D, eCell{k}(:,a)];                                   %#ok<AGROW>
            end
            for c = 1:numel(xNamesCell{k})            % then Acc_*, Gyr_*
                if c == pk, continue; end
                vn{end+1} = sprintf('%s_%s', pre, xNamesCell{k}{c});      %#ok<SAGROW>
                D = [D, xCell{k}(:,c)];                                   %#ok<AGROW>
            end
        end
        if hasData
            writetable(array2table(round(D,4),'VariableNames',matlab.lang.makeValidName(vn)), xlsFile, 'Sheet', sheet);
            nSheets = nSheets + 1;
        end
    end
    if ~isempty(jU)                                    % last sheet: joints
        vnJ = matlab.lang.makeValidName([{'time_s'}, jLabels(:)']);
        writetable(array2table(round([tg(:), jU],4),'VariableNames',vnJ), xlsFile, 'Sheet', 'Joints');
        nSheets = nSheets + 1;
    end
    fprintf('\nExported Excel workbook (%d sheets, %d rows each):\n  %s\n', nSheets, numel(tg), xlsFile);

    %% --- Save a tidy struct to .mat (and keep it in the workspace) ---
    Data = struct();
    Data.test = subjectNumber;
    Data.fs   = TARGET_RATE;
    Data.time = tg;
    Data.sync = struct('shiftAw_s', shiftAw, 'peakAwinda_s', tLA, 'peakDot_s', tLD, ...
                       'leftFootDelay_s', tLA - tLD, 'rightFootDelay_s', tRA - tRD);
    Data.imu = struct('label',{},'system',{},'body',{}, ...
                      'euler_ZXY_deg',{},'packet',{},'acc',{},'gyro',{},'quat',{});
    for i = 1:nItem
        tok = regexp(labels{i}, '^(.*) \((Awinda|Dot)\)$', 'tokens', 'once');
        pk = find(strcmp(xNamesCell{i},'Packet'), 1);
        ai = find(startsWith(xNamesCell{i},'Acc_'));
        gi = find(startsWith(xNamesCell{i},'Gyr_'));
        Data.imu(i).label         = labels{i};
        Data.imu(i).body          = tok{1};
        Data.imu(i).system        = tok{2};
        Data.imu(i).euler_ZXY_deg = eCell{i};
        Data.imu(i).packet        = xCell{i}(:,pk);
        Data.imu(i).acc           = xCell{i}(:,ai);
        Data.imu(i).gyro          = xCell{i}(:,gi);
        Data.imu(i).quat          = qCell{i};        % raw orientation quaternion [w x y z]
    end
    Data.joints = struct('labels', {jLabels}, 'angles_deg', jU);
    matFile = fullfile(outDir, sprintf('AllData_Test%d.mat', subjectNumber));
    save(matFile, 'Data');
    fprintf('Saved struct ''Data'' to workspace and file:\n  %s\n', matFile);
end

%% ========================================================================
%  LOCAL FUNCTIONS
%% ========================================================================
function updatePlot(hFig)
    S = guidata(hFig);
    selAng = find(arrayfun(@(h) h.Value==1, S.angCb));   % subset of [1 2 3] = [Z X Y]
    style  = S.styleItems{S.styleDD.Value};
    useLine = any(strcmp(style,{'Line','Both'}));
    useScat = any(strcmp(style,{'Scatter','Both'}));
    multiA  = numel(selAng) > 1;
    cla(S.ax); hold(S.ax,'on');
    legH = []; legN = {};
    for i = 1:S.n
        if S.cb(i).Value ~= 1, continue; end
        t = S.time{i}; col = S.color(i,:);
        for a = selAng(:)'
            y = S.euler{i}(:,a);
            mk = 'none'; if multiA, mk = S.angMarkers{a}; end
            h = [];
            if useLine
                if strcmp(mk,'none')
                    h = plot(S.ax, t, y, '-', 'Color', col, 'LineWidth', S.LINE_WIDTH);
                else
                    step = max(1, round(numel(t)/25));
                    h = plot(S.ax, t, y, '-', 'Color', col, 'LineWidth', S.LINE_WIDTH, ...
                             'Marker', mk, 'MarkerIndices', 1:step:numel(t), 'MarkerSize', 5);
                end
            end
            if useScat
                smk = 'o'; if multiA, smk = S.angMarkers{a}; end
                hs = scatter(S.ax, t, y, S.SCATTER_SIZE, col, smk, 'filled');
                if isempty(h), h = hs; end
            end
            if multiA, name = [S.label{i} ' - ' S.angShort{a}]; else, name = S.label{i}; end
            legH(end+1) = h;     %#ok<AGROW>
            legN{end+1} = name;  %#ok<AGROW>
        end
    end
    hold(S.ax,'off');
    S.ax.FontName=S.FONT_NAME; S.ax.FontSize=S.TICK_SIZE; S.ax.FontWeight='bold';
    S.ax.LineWidth=S.BOX_LINE_WIDTH; S.ax.Box='on';
    if S.GRID_ON, grid(S.ax,'on'); end
    if numel(selAng) == 1, yl = S.angFull{selAng}; else, yl = 'Euler angle (deg)'; end
    xlabel(S.ax,'Time (s)','FontSize',S.XLABEL_SIZE,'FontWeight','bold','FontName',S.FONT_NAME);
    ylabel(S.ax,yl,'FontSize',S.YLABEL_SIZE,'FontWeight','bold','FontName',S.FONT_NAME,'Interpreter','none');
    angTxt = strjoin(S.angShort(selAng), ',');
    title(S.ax,[S.titleStr '   -   Euler ' angTxt],'FontSize',S.TITLE_SIZE,'FontWeight','bold', ...
          'FontName',S.FONT_NAME,'Interpreter','none');
    if S.LEGEND_ON && ~isempty(legH)
        legend(S.ax, legH, legN, 'Location','eastoutside', ...
            'FontSize',S.LEGEND_SIZE,'FontName',S.FONT_NAME,'Interpreter','none');
    else
        legend(S.ax,'off');
    end
end

function setAll(hFig, val)
    S = guidata(hFig);
    for i = 1:S.n, S.cb(i).Value = val; end
    updatePlot(hFig);
end

function savePNG(hFig)
    S = guidata(hFig);
    if ~exist(S.figDir,'dir'), mkdir(S.figDir); end
    selAng = find(arrayfun(@(h) h.Value==1, S.angCb));
    tag = strjoin(S.angShort(selAng), '');
    if isempty(tag), tag = 'none'; end
    pngFile = fullfile(S.figDir, sprintf('IMU_Euler%s_Test%d.png', tag, S.subjectNumber));
    exportgraphics(hFig, pngFile, 'Resolution', S.EXPORT_RESOLUTION);
    fprintf('PNG saved: %s\n', pngFile);
end

function fp = findFile(dataDir, pattern)
    d = dir(fullfile(dataDir, pattern));
    if isempty(d), fp = ''; else, fp = fullfile(dataDir, d(1).name); end
end

function p = unwrapCounter(p, modulus)
% Undo the rollover of a fixed-width sample counter (Awinda's PacketCounter is
% 16-bit and wraps 65535 -> 0). Each backward jump larger than half the modulus
% is one wrap; add the modulus to every sample after it so the counter becomes
% monotonic and packet-derived time stays increasing. Forward gaps (dropped
% packets) are left untouched.
    p = p(:);
    if numel(p) < 2, return; end
    wraps = cumsum(diff(p) < -modulus/2);   % +1 at each rollover
    p(2:end) = p(2:end) + wraps * modulus;
end

function [cols, M] = readIMUFile(file)
% Read an Xsens Awinda (.txt, tab) or Movella Dot (.csv, comma) IMU file.
    fid = fopen(file,'r');
    if fid < 0, error('Cannot open %s', file); end
    headerLine = '';
    while true
        line = fgetl(fid);
        if ~ischar(line), fclose(fid); error('No PacketCounter header in %s', file); end
        if contains(line,'PacketCounter'), headerLine = line; break; end
    end
    if contains(headerLine, sprintf('\t')), delim = sprintf('\t'); else, delim = ','; end
    cols = strtrim(strsplit(strtrim(headerLine), delim));
    C = textscan(fid, repmat('%f',1,numel(cols)), 'Delimiter', delim, ...
                 'CollectOutput', true, 'EmptyValue', NaN);
    fclose(fid);
    M = C{1};
end

function Q = getQuatCols(cols, M)
% Return N x 4 quaternion [w x y z], handling both naming schemes.
    names = {'Quat_W','Quat_X','Quat_Y','Quat_Z'; 'Quat_q0','Quat_q1','Quat_q2','Quat_q3'};
    for r = 1:size(names,1)
        idx = zeros(1,4); ok = true;
        for k = 1:4
            j = find(strcmpi(cols, names{r,k}), 1);
            if isempty(j), ok = false; break; end
            idx(k) = j;
        end
        if ok, Q = M(:, idx); return; end
    end
    error('Quaternion columns not found (looked for Quat_W.. or Quat_q0..).');
end

function Q = contigQuat(Q)
% Enforce sign continuity (q and -q are the same rotation) so the quaternion can
% be interpolated safely across samples. Vectorized: the cumulative sign is the
% running product of the signs of consecutive raw dot products.
    if size(Q,1) < 2, return; end
    r = sum(Q(2:end,:) .* Q(1:end-1,:), 2);   % raw consecutive dot products
    s = sign(r);  s(s == 0) = 1;
    S = cumprod([1; s]);                      % ±1 sign to apply to each sample
    Q = Q .* S;
end

function [tp, vp] = footPeak(labels, tCell, eCell, name, col, minDeg)
% Time/value of the first POSITIVE peak of one trace's column that reaches
% minDeg - i.e. the first foot-lift. With the per-system Euler sequences the
% lift is positive for both systems, so we look for a positive peak (no
% magnitude auto-flip, which could otherwise lock onto a negative gait swing).
    tp = NaN; vp = NaN;
    i = find(strcmp(labels, name), 1);
    if isempty(i), return; end
    t = tCell{i}; x = eCell{i}(:, col);
    for k = 2:numel(x)-1
        if x(k) >= minDeg && x(k) >= x(k-1) && x(k) > x(k+1)
            tp = t(k); vp = x(k); return;        % first positive local max above threshold
        end
    end
    k = find(x >= minDeg, 1);                    % fallback: first threshold crossing
    if ~isempty(k), tp = t(k); vp = x(k); end
end

function E = quatEuler(Q, seq)
% Euler angles (deg) for the given sequence, always returned in [Z X Y] column
% order (so the rest of the pipeline keeps X = column 2). Each system uses the
% sequence that puts its X on a smooth atan2 axis: Awinda='ZXY', Dot='ZYX'.
    if exist('quaternion', 'class') ~= 8
        error(['The quaternion class is required (Sensor Fusion and Tracking, ' ...
               'Navigation, or Robotics System Toolbox).']);
    end
    E = eulerd(quaternion(Q), seq, 'frame');
    if strcmp(seq, 'ZYX'), E = E(:, [1 3 2]); end   % [Z Y X] -> [Z X Y]
    % 'ZXY' already returns [Z X Y]
end

function [t, data, labels] = readMot(file)
% Read an OpenSim .mot/.sto (skip header to 'endheader', tab-delimited).
    fid = fopen(file,'r'); if fid < 0, error('Cannot open %s', file); end
    line = fgetl(fid);
    while ischar(line) && ~strcmpi(strtrim(line), 'endheader'), line = fgetl(fid); end
    labels = strsplit(strtrim(fgetl(fid)), sprintf('\t'));
    C = cell2mat(textscan(fid, repmat('%f',1,numel(labels)), 'Delimiter','\t', 'CollectOutput', true));
    fclose(fid);
    t = C(:,1); data = C(:,2:end); labels = labels(2:end);
end

function buildComboViewer(titleStr, T, Y, L, defOn, fontName, figDir, subjNum)
% Interactive viewer of arbitrary time series (IMU Euler + joint angles).
% A multi-select listbox (scrolls natively) chooses which traces to plot.
    n = numel(L);
    if exist('turbo','file'), cmap = turbo(n); else, cmap = hsv(n); end
    hF = figure('Color','w','Name',titleStr,'Position',[80 80 1380 800]);
    ax = axes(hF,'Position',[0.34 0.10 0.63 0.82]);
    LX = 0.015;
    uicontrol(hF,'Style','text','Units','normalized','Position',[LX 0.95 0.10 0.03], ...
        'String','Plot style:','BackgroundColor','w','FontName',fontName,'FontWeight','bold','HorizontalAlignment','left');
    sItems = {'Line','Scatter','Both'};
    sDD = uicontrol(hF,'Style','popupmenu','Units','normalized','Position',[LX+0.10 0.952 0.12 0.03], ...
        'String',sItems,'Value',1,'FontName',fontName,'Callback',@(~,~) updateCombo(hF));
    uicontrol(hF,'Style','pushbutton','Units','normalized','Position',[LX+0.23 0.952 0.075 0.03], ...
        'String','Save PNG','FontName',fontName,'Callback',@(~,~) savePNGcombo(hF));
    uicontrol(hF,'Style','text','Units','normalized','Position',[LX 0.915 0.31 0.025], ...
        'String','Select traces (Ctrl/Shift-click for multiple):','BackgroundColor','w', ...
        'FontName',fontName,'HorizontalAlignment','left');
    defIdx = find(ismember(L, defOn)); if isempty(defIdx), defIdx = 1; end
    lb = uicontrol(hF,'Style','listbox','Units','normalized','Position',[LX 0.03 0.31 0.88], ...
        'String',L,'Min',0,'Max',n,'Value',defIdx,'FontName',fontName,'FontSize',9, ...
        'Callback',@(~,~) updateCombo(hF));
    S = struct('ax',ax,'lb',lb,'T',{T},'Y',{Y},'L',{L},'color',cmap,'sDD',sDD, ...
               'sItems',{sItems},'titleStr',titleStr,'fontName',fontName,'figDir',figDir,'subjNum',subjNum);
    guidata(hF, S); updateCombo(hF);
end

function updateCombo(hF)
    S = guidata(hF); idx = get(S.lb,'Value'); ax = S.ax;
    style = S.sItems{S.sDD.Value};
    useLine = any(strcmp(style,{'Line','Both'})); useScat = any(strcmp(style,{'Scatter','Both'}));
    cla(ax); hold(ax,'on'); legH = []; legN = {};
    for k = idx(:)'
        c = S.color(k,:); h = [];
        if useLine, h = plot(ax, S.T{k}, S.Y{k}, '-', 'Color', c, 'LineWidth', 1.6); end
        if useScat, hs = scatter(ax, S.T{k}, S.Y{k}, 14, c, 'filled'); if isempty(h), h = hs; end; end
        legH(end+1) = h; legN{end+1} = S.L{k}; %#ok<AGROW>
    end
    hold(ax,'off'); grid(ax,'on'); box(ax,'on');
    ax.FontName = S.fontName; ax.FontSize = 12; ax.FontWeight = 'bold';
    xlabel(ax,'Time (s)','FontSize',15,'FontWeight','bold','FontName',S.fontName);
    ylabel(ax,'Angle (deg)','FontSize',15,'FontWeight','bold','FontName',S.fontName);
    title(ax,S.titleStr,'FontSize',17,'FontWeight','bold','FontName',S.fontName,'Interpreter','none');
    if ~isempty(legH)
        legend(ax, legH, legN, 'Location','eastoutside','Interpreter','none','FontSize',9);
    else
        legend(ax,'off');
    end
end

function savePNGcombo(hF)
    S = guidata(hF);
    if ~exist(S.figDir,'dir'), mkdir(S.figDir); end
    pngFile = fullfile(S.figDir, sprintf('Combined_Joints_IMU_Test%d.png', S.subjNum));
    exportgraphics(hF, pngFile, 'Resolution', 300);
    fprintf('PNG saved: %s\n', pngFile);
end
