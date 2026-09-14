% diag_drift_check.m — Cross-trial IMU heading-drift diagnostic
% ------------------------------------------------------------------------
% Answers the question: is the drift bound to a SENSOR (a bad unit that is
% worst in every trial) or to the TURN / environment (worst on the turning
% trials, cleanest on the straight one)?
%
% Run from the Analysis/ folder. Prompts for one or more Test numbers
% (e.g. "25 26 27") and prints, side by side per sensor:
%   tiltDrift   - slow trend range of the gravity-anchored tilt (the CLEAN
%                 channel; should stay small — a sanity control).
%   headDrift   - slow trend range of the swing-twist heading RELATIVE to the
%                 segment's reference (legs->pelvis, arms->torso). This is the
%                 channel that drifts. Real turning is common-mode with the
%                 reference and cancels, so what remains is differential drift.
%   IKmean/max  - per-IMU OpenSim orientation-tracking error (deg) if the IK
%                 has been run (reads IKResults/, and IKResults_dedrift/ if
%                 present). The trustworthy quality gate: healthy < ~10 deg.
%
% Read-only. Touches nothing the pipeline produces. See the Obsidian notes
% "Heading Drift and De-drift" and "Lab Checklist - IMU Drift".
% ------------------------------------------------------------------------

clear; clc;
DATA_RATE = 40;          % Awinda sample rate (Hz)
TREND_WIN_S = 10;        % moving-average window for the slow drift trend (s)

% Awinda sensor ID -> body segment (from the README sensor map)
ID = { '00B4AB22','pelvis'; '00B4AB26','torso';
       '00B4AB23','foot_L'; '00B4AB29','foot_R';
       '00B4AB2D','thigh_L';'00B4AB24','thigh_R';   % right thigh 2B->24 (Test 28+)
       '00B4AB25','shank_L';'00B4AB30','shank_R';   % right shank 27->30 (Test 28+)
       '00B4AB2B','thigh_R';'00B4AB27','shank_R';   % old right-leg serials (Test <=27)
       '00B4AB2E','uarm_L'; '00B4AB31','uarm_R';
       '00B4AB28','farm_L'; '00B4AB2F','farm_R' };
% reference segment each limb segment is locked/compared to
REF = struct('thigh_L','pelvis','thigh_R','pelvis','shank_L','pelvis', ...
             'shank_R','pelvis','foot_L','pelvis','foot_R','pelvis', ...
             'uarm_L','torso','uarm_R','torso','farm_L','torso','farm_R','torso');
% print order
ORDER = {'pelvis','torso','thigh_R','shank_R','foot_R', ...
         'thigh_L','shank_L','foot_L','uarm_R','farm_R','uarm_L','farm_L'};
% IK .sto column header -> our segment name
IKMAP = struct('pelvis_imu','pelvis','torso_imu','torso', ...
    'femur_r_imu','thigh_R','tibia_r_imu','shank_R','calcn_r_imu','foot_R', ...
    'femur_l_imu','thigh_L','tibia_l_imu','shank_L','calcn_l_imu','foot_L', ...
    'humerus_r_imu','uarm_R','ulna_r_imu','farm_R', ...
    'humerus_l_imu','uarm_L','ulna_l_imu','farm_L');

% ---- locate the project root (parent of Analysis/) ----
here = fileparts(mfilename('fullpath'));
if isempty(here), here = pwd; end
root = fileparts(here);
awindaRoot  = fullfile(root, 'Data', 'Awinda IMUs');
outputsRoot = fullfile(root, 'Results', 'OpenSim Outputs');

resp = input('Test number(s) to check (e.g. 25 26 27): ', 's');
tests = str2num(resp); %#ok<ST2NM>
if isempty(tests), error('No valid test numbers given.'); end

R = struct();   % results per test
for t = tests
    R.(sprintf('t%d',t)) = analyzeTest(t, awindaRoot, outputsRoot, ...
                            ID, REF, IKMAP, DATA_RATE, TREND_WIN_S);
end

% ---------------------------- print tables ----------------------------
printTable('RAW heading drift vs reference (deg)   [tilt = clean control]', ...
    tests, R, ORDER, {'tilt','head'}, {'tiltDrift','headDrift'});
printTable('OpenSim IK tracking error — RAW IKResults (deg)', ...
    tests, R, ORDER, {'ikMean','ikMax'}, {'mean','max'});
if any(structfun(@(s) s.hasDD, R))
    printTable('OpenSim IK tracking error — DE-DRIFTED IKResults_dedrift (deg)', ...
        tests, R, ORDER, {'ddMean','ddMax'}, {'mean','max'});
end

fprintf(['\nInterpretation:\n' ...
 '  * A sensor whose headDrift/IK error is high in EVERY test  -> that UNIT (MFM/RMA).\n' ...
 '  * Drift that tracks turning (straight test lowest; a turn side worst) -> ENVIRONMENT/turn.\n' ...
 '  * pelvis/torso must be near-clean: they are the heading-lock reference.\n\n']);

% ============================ functions ============================
function out = analyzeTest(t, awindaRoot, outputsRoot, ID, REF, IKMAP, fs, winS)
    out = struct('test',t,'hasDD',false);
    dataDir = fullfile(awindaRoot, sprintf('Test %d', t));
    files = dir(fullfile(dataDir, 'MT_*.txt'));
    Q = struct();
    for k = 1:numel(files)
        tok = regexp(files(k).name, '(00B4AB[0-9A-Fa-f]{2})', 'tokens', 'once');
        if isempty(tok), continue; end
        id = upper(tok{1});
        row = find(strcmpi(ID(:,1), id), 1);
        if isempty(row), continue; end
        Q.(ID{row,2}) = readQuat(fullfile(dataDir, files(k).name));
    end
    segs = fieldnames(Q);
    if isempty(segs)
        warning('Test %d: no raw MT_*.txt found (only .mtb?). Run step1 to convert.', t);
    else
        n = min(structfun(@(q) size(q,1), Q));
        out.nSec = n/fs;
        for i = 1:numel(segs)
            s = segs{i};  q = Q.(s)(1:n,:);
            out.tilt.(s) = trendRange(tiltDeg(q), fs, winS);
            hs = rad2deg(headingRad(q));
            if isfield(REF, s) && isfield(Q, REF.(s))
                hr = rad2deg(headingRad(Q.(REF.(s))(1:n,:)));
                out.head.(s) = trendRange(hs - hr, fs, winS);
            else
                out.head.(s) = NaN;   % pelvis/torso: absolute heading = real turning, not drift
            end
        end
    end
    % IK tracking errors (raw + de-drifted) if present
    ikDir = fullfile(outputsRoot, sprintf('Test %d', t), 'IKResults');
    [out.ikMean, out.ikMax] = readIKErr(ikDir, IKMAP, false);
    ddDir = fullfile(outputsRoot, sprintf('Test %d', t), 'IKResults_dedrift');
    if isfolder(ddDir)
        [out.ddMean, out.ddMax] = readIKErr(ddDir, IKMAP, true);
        out.hasDD = ~isempty(fieldnames(out.ddMean));
    end
end

function [M, X] = readIKErr(ikDir, IKMAP, wantDedrift)
    M = struct(); X = struct();
    if ~isfolder(ikDir), return; end
    pat = ternary(wantDedrift, '*dedrift*orientationErrors.sto', '*orientationErrors.sto');
    ef = dir(fullfile(ikDir, pat));
    ef = ef(~contains({ef.name},'dedrift') | wantDedrift);   % raw dir: skip any dedrift
    if isempty(ef), return; end
    [~,idx] = max([ef.datenum]);  f = fullfile(ikDir, ef(idx).name);
    L = readlines(f); hi = find(strcmp(strip(L),'endheader'),1);
    hdr = split(strip(L(hi+1)), sprintf('\t'));
    D = []; for j = hi+2:numel(L)
        s = strip(L(j)); if s=="", continue; end
        D = [D; str2double(split(s, sprintf('\t')))']; %#ok<AGROW>
    end
    for c = 2:numel(hdr)
        name = char(hdr(c));
        if ~isfield(IKMAP, name), continue; end
        seg = IKMAP.(name); col = D(:,c);
        M.(seg) = mean(col,'omitnan')*180/pi;
        X.(seg) = max(col)*180/pi;
    end
end

function printTable(title, tests, R, ORDER, subFields, colTags)
    fprintf('\n===== %s =====\n', title);
    hdr = sprintf('%-9s', 'sensor');
    for t = tests, for c = 1:numel(colTags)
        hdr = [hdr sprintf('%12s', sprintf('T%d.%s', t, colTags{c}))]; end; end
    fprintf('%s\n', hdr);
    for i = 1:numel(ORDER)
        s = ORDER{i}; line = sprintf('%-9s', s); any_ = false;
        for t = tests
            r = R.(sprintf('t%d',t));
            for c = 1:numel(subFields)
                v = NaN; sf = subFields{c};
                if isfield(r, sf) && isfield(r.(sf), s), v = r.(sf).(s); any_ = true; end
                if isnan(v), line = [line sprintf('%12s','-')];
                else,        line = [line sprintf('%12.1f', v)]; end
            end
        end
        if any_, fprintf('%s\n', line); end
    end
end

function q = readQuat(fp)
    L = readlines(fp); q = [];
    for i = 1:numel(L)
        s = char(L(i));
        if isempty(s) || s(1)=='/' || startsWith(s,'PacketCounter'), continue; end
        p = str2double(split(strip(string(s))));
        if numel(p) >= 8, q = [q; p(5:8)']; end %#ok<AGROW>  % Quat_q0..q3 = w x y z
    end
end

function h = headingRad(Q)   % swing-twist heading about world-up (matches step1)
    h = unwrap(2*atan2(Q(:,4), Q(:,1)));
end
function d = tiltDeg(Q)      % angle of sensor z-axis from world vertical
    x=Q(:,2); y=Q(:,3);  zz = 1 - 2*(x.^2 + y.^2);
    d = acosd(min(max(zz,-1),1));
end
function r = trendRange(sig, fs, winS)
    w = round(winS*fs); if mod(w,2)==0, w=w+1; end
    if numel(sig) <= w, r = max(sig)-min(sig); return; end
    tr = movmean(sig, w, 'Endpoints','discard');
    r = max(tr) - min(tr);
end
function v = ternary(c,a,b), if c, v=a; else, v=b; end, end
