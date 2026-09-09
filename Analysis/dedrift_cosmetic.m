clc
clear all
close all
addpath(fileparts(mfilename('fullpath')));
%% ========================================================================
%% COSMETIC de-drift of IK joint angles  ***  NOT METROLOGICALLY VALID  ***
%% ------------------------------------------------------------------------
%%  This bounds badly-drifted joint angles into a plausible range for a QUICK
%%  QUALITATIVE / VISUAL look ONLY. It does NOT recover the true joint angles.
%%  On the drift-wrecked trials (e.g. 101, 21, 22, 24) the right/left-leg IMU
%%  heading is wrong by 40-80 deg, which rotates the sagittal plane and cannot
%%  be undone by post-processing. DO NOT report, publish, or compute metrics
%%  (peak flexion, clearance, angular momentum, crossing-vs-level stats) from
%%  the output of this script. For trustworthy angles you need either a clean
%%  recapture (onboard AHS / VRU profile) or a camera-referenced correction.
%%
%%  Method (transparent):
%%    drift(t) = movmedian(raw, DRIFT_WIN)              % slow wander estimate
%%    de(t)    = raw(t) - ( drift(t) - drift(start) )   % remove drift vs the
%%                                                        trusted start posture
%%    de(t)    = clamp(de(t), physiological range)      % hard bound (cosmetic)
%%  The clamp does real clipping here (that is the point) - the % clipped is
%%  printed per joint so you can see how much is fabricated.
%% ========================================================================

%% ----- Input -----
subj_raw = input('  Input Test Number: ', 's');
if isempty(subj_raw), tn = 101; else, tn = str2double(subj_raw); end

%% ----- Settings (edit freely) -----
DRIFT_WIN_SEC = 1.5;   % moving-median window for the drift estimate (s). Smaller = flatter.
ANCHOR_SEC    = 5.0;   % early window used as the "good start" reference (s)
DO_CLAMP      = true;  % hard-bound each joint to a plausible range (cosmetic)
JOINTS_SHOW   = {'hip_flexion_r','knee_angle_r','ankle_angle_r', ...
                 'hip_flexion_l','knee_angle_l','ankle_angle_l'};

% Plausible walking ranges (deg), Rajagopal sign convention (+hip flex, -knee flex,
% +ankle dorsiflex). Generous to allow obstacle-crossing excursions. Unlisted
% rotational coords use GENERIC; translations (tx/ty/tz) are left untouched.
CLAMP = containers.Map('KeyType','char','ValueType','any');
CLAMP('hip_flexion_r')  = [-30 120];  CLAMP('hip_flexion_l')  = [-30 120];
CLAMP('hip_adduction_r')= [-40  40];  CLAMP('hip_adduction_l')= [-40  40];
CLAMP('hip_rotation_r') = [-60  60];  CLAMP('hip_rotation_l') = [-60  60];
CLAMP('knee_angle_r')   = [-150 15];  CLAMP('knee_angle_l')   = [-150 15];
CLAMP('ankle_angle_r')  = [-50  40];  CLAMP('ankle_angle_l')  = [-50  40];
CLAMP('subtalar_angle_r')=[-40 40];   CLAMP('subtalar_angle_l')=[-40 40];
CLAMP('arm_flex_r')     = [-60 180];  CLAMP('arm_flex_l')     = [-60 180];
CLAMP('arm_add_r')      = [-90  90];  CLAMP('arm_add_l')      = [-90  90];
CLAMP('elbow_flex_r')   = [  0 150];  CLAMP('elbow_flex_l')   = [  0 150];
CLAMP('lumbar_extension')=[-40 40];   CLAMP('lumbar_bending') = [-40 40];
CLAMP('lumbar_rotation')= [-40 40];
GENERIC = [-120 120];

%% ----- Locate + read the IK .mot -----
ikDir = fullfile('..','Results','OpenSim Outputs',['Test ' num2str(tn)],'IKResults');
f = dir(fullfile(ikDir,'ik_*.mot'));
f = f(~contains({f.name},'COSMETIC'));           % never re-de-drift our own output
if isempty(f), error('No ik_*.mot in %s. Run step 1 first.', ikDir); end
[~,newest] = max([f.datenum]);
motFile = fullfile(ikDir, f(newest).name);
fprintf('Loading: %s\n', motFile);
[t, data, labels] = readMot(motFile);
fs = 1/median(diff(t),'omitnan');
win = max(3, round(DRIFT_WIN_SEC*fs)); if mod(win,2)==0, win=win+1; end

%% ----- De-drift every rotational coordinate -----
de = data;
clipPct = zeros(1,numel(labels));
isTrans = @(nm) endsWith(nm,'_tx')||endsWith(nm,'_ty')||endsWith(nm,'_tz');
for i = 1:numel(labels)
    nm = labels{i};
    if isTrans(nm), continue; end                % leave pelvis translations alone
    y = data(:,i);
    if all(~isfinite(y)) || range(y(isfinite(y)))<1e-6, continue; end
    mid = movmedian(y, win, 'omitnan');
    anchor = median(mid(t - t(1) < ANCHOR_SEC), 'omitnan');
    d = y - (mid - anchor);
    if DO_CLAMP
        if isKey(CLAMP, nm), rg = CLAMP(nm); else, rg = GENERIC; end
        clipPct(i) = 100*mean(d<rg(1) | d>rg(2), 'omitnan');
        d = min(max(d, rg(1)), rg(2));
    end
    de(:,i) = d;
end

%% ----- Report how much was fabricated (clipped) -----
fprintf('\n*** COSMETIC de-drift - NOT VALID for analysis ***\n');
fprintf('%-16s %10s %12s %8s\n','coord','rawRange','newRange','%%clipped');
for k = 1:numel(JOINTS_SHOW)
    i = find(strcmp(labels, JOINTS_SHOW{k}),1); if isempty(i), continue; end
    fprintf('%-16s %10.0f %12.0f %8.1f\n', JOINTS_SHOW{k}, ...
        range(data(isfinite(data(:,i)),i)), range(de(isfinite(de(:,i)),i)), clipPct(i));
end

%% ----- Write a clearly-flagged .mot -----
[~,base] = fileparts(motFile);
% NOTE: name does NOT start with 'ik_' so step2/step4/etc (which load the newest
% ik_*.mot) can never pick up this cosmetic file by accident.
outFile = fullfile(ikDir, ['COSMETIC_NOT_VALID_' base '.mot']);
writeMotCosmetic(outFile, t, de, labels);
fprintf('\nWrote (flagged, NOT picked up by step2/4): %s\n', outFile);

%% ----- Before/after plot with a loud watermark -----
figure('Color','w','Name',sprintf('COSMETIC de-drift (NOT VALID) | Test %d', tn), ...
       'Position',[60 60 1250 760]);
for k = 1:numel(JOINTS_SHOW)
    i = find(strcmp(labels, JOINTS_SHOW{k}),1);
    ax = subplot(2,3,k); hold(ax,'on');
    if isempty(i), title(ax,[JOINTS_SHOW{k} ' (n/a)'],'Interpreter','none'); continue; end
    plot(ax, t, data(:,i), '-', 'Color',[0.80 0.30 0.30 0.35], 'LineWidth',0.7);
    plot(ax, t, de(:,i),   '-', 'Color',[0.10 0.35 0.75], 'LineWidth',1.4);
    grid(ax,'on'); box(ax,'on'); xlabel(ax,'Time (s)'); ylabel(ax,'Angle (deg)');
    title(ax, sprintf('%s  (%.0f%% clipped)', JOINTS_SHOW{k}, clipPct(i)), 'Interpreter','none','FontSize',10);
end
sgtitle('COSMETIC de-drift - blue=bounded, red=raw.  *** NOT METROLOGICALLY VALID - do not analyse ***', ...
        'FontWeight','bold','Color',[0.75 0 0]);
annotation('textbox',[0.15 0.35 0.7 0.3],'String','NOT VALID', ...
    'FontSize',80,'Color',[0.85 0 0 ],'FontWeight','bold', ...
    'HorizontalAlignment','center','VerticalAlignment','middle', ...
    'EdgeColor','none','FitBoxToText','off','Interpreter','none');

fprintf('Done. Reminder: use this ONLY for a quick visual - not for any numbers.\n');

%% ========================================================================
%  LOCAL FUNCTIONS
%% ========================================================================
function [t, data, labels] = readMot(file)
    fid = fopen(file,'r'); if fid<0, error('Cannot open %s', file); end
    line = fgetl(fid);
    while ischar(line) && ~strcmpi(strtrim(line),'endheader'), line = fgetl(fid); end
    labels = strsplit(strtrim(fgetl(fid)), sprintf('\t'));
    M = cell2mat(textscan(fid, repmat('%f',1,numel(labels)), 'Delimiter','\t','CollectOutput',true));
    fclose(fid);
    t = M(:,1); data = M(:,2:end); labels = labels(2:end);
end

function writeMotCosmetic(file, t, data, labels)
% Write an OpenSim .mot (inDegrees=yes) with a loud NOT-VALID banner in the header.
    fid = fopen(file,'w'); if fid<0, error('Cannot write %s', file); end
    nR = numel(t); nC = numel(labels) + 1;
    fprintf(fid, 'COSMETIC_dedrift_NOT_METROLOGICALLY_VALID\n');
    fprintf(fid, '# WARNING: cosmetic drift-bounding for visualisation only.\n');
    fprintf(fid, '# These joint angles are NOT accurate. Do not analyse, report, or publish.\n');
    fprintf(fid, 'version=1\n');
    fprintf(fid, 'nRows=%d\n', nR);
    fprintf(fid, 'nColumns=%d\n', nC);
    fprintf(fid, 'inDegrees=yes\n');
    fprintf(fid, 'endheader\n');
    fprintf(fid, 'time'); fprintf(fid, '\t%s', labels{:}); fprintf(fid, '\n');
    for r = 1:nR
        fprintf(fid, '%.8g', t(r));
        fprintf(fid, '\t%.6f', data(r,:));
        fprintf(fid, '\n');
    end
    fclose(fid);
end
