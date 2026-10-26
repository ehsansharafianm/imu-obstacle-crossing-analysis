function diag_participant(tn, root)
% DIAG_PARTICIPANT  One-shot drift QC for one test, so you know up front what needs
% attention (and what to hand-calc). Run AFTER step1 (IK + de-drift) and step3/4/7.
%   diag_participant(108)
%
% Prints four things:
%   [1] per-IMU tracking error (raw vs de-drift) - the drift fingerprint
%   [2] de-drift AUTO verdict per joint (which take de-drift, which stay raw)
%   [3] left/right sign check (a mismatch = possible flipped calibration)
%   [4] joint max/min per obstacle that look NON-PHYSIOLOGICAL -> hand-calc candidates
    if nargin < 2 || isempty(root), root = fileparts(fileparts(mfilename('fullpath'))); end
    od = fullfile(root,'Results','OpenSim Outputs',  ['Test ' num2str(tn)]);
    pd = fullfile(root,'Results','Parameters Output',['Test ' num2str(tn)]);
    fprintf('\n===================== QC: Test %d =====================\n', tn);

    % ---- [1] IMU tracking errors (raw vs de-drift) ----
    eR = readErr(latest(fullfile(od,'IKResults'),        '*orientationErrors.sto'));
    eD = readErr(latest(fullfile(od,'IKResults_dedrift'),'*orientationErrors.sto'));
    fprintf('\n[1] IMU tracking error (deg; healthy < ~10):\n');
    if isempty(fieldnames(eR))
        fprintf('    (no raw IK errors found - run step1 first)\n');
    else
        fprintf('    %-14s %8s %10s\n','IMU','raw','de-drift');
        for ks = fieldnames(eR)'
            r = eR.(ks{1});  d = getf(eD, ks{1}, NaN);  fl = '';  if r > 10, fl = '   <-- drift'; end
            if isfinite(d), fprintf('    %-14s %8.1f %10.1f%s\n', ks{1}, r, d, fl);
            else,           fprintf('    %-14s %8.1f %10s%s\n',   ks{1}, r, '-', fl); end
        end
    end

    % ---- [2] de-drift AUTO verdict per joint ----
    fprintf('\n[2] De-drift AUTO verdict (what step3 [Enter]=auto will use):\n');
    if isempty(fieldnames(eR)) || isempty(fieldnames(eD))
        fprintf('    (need both raw + de-drift errors; run step1 with de-drift = y)\n');
    else
        for jl = {'hip_flexion_l','hip_flexion_r','knee_angle_l','knee_angle_r','ankle_angle_l','ankle_angle_r'}
            imus = jointIMUs(jl{1});  useDd = ~isempty(imus);  det = '';
            for q = 1:numel(imus)
                er = getf(eR, imus{q}, inf);  ed = getf(eD, imus{q}, inf);
                if ~(ed <= er - 1), useDd = false; end
                det = [det sprintf(' %s %.0f->%.0f', imus{q}, er, ed)]; %#ok<AGROW>
            end
            v = 'raw';  if useDd, v = 'DE-DRIFT'; end
            fprintf('    %-15s -> %-8s |%s\n', jl{1}, v, det);
        end
    end

    % ---- load segmented data ----
    sgF = fullfile(pd, sprintf('SegmentedParams_Test%d.mat', tn));
    s5F = fullfile(pd, sprintf('SegTrajectories_WithCamera_Test%d.mat', tn));
    if ~isfile(sgF) || ~isfile(s5F)
        fprintf('\n(SegmentedParams / SegTrajectories missing - run step4 and step7 for [3]/[4])\n');
        fprintf('=======================================================\n');  return;
    end
    d = load(sgF);  Sg = d.Seg;
    g = load(s5F);  fn = fieldnames(g);  S5 = g.(fn{1});

    % ---- [3] sign check (left vs right dominant direction) ----
    fprintf('\n[3] Sign check (left vs right dominant direction):\n');
    for jc = {'hip_flexion','knee_angle','ankle_angle'}
        dl = sideDom(Sg, jc{1}, 'l');  dr = sideDom(Sg, jc{1}, 'r');
        tag = '';  if ~isempty(dl) && ~isempty(dr) && ~strcmp(dl,dr), tag = '   <-- MISMATCH (check calibration)'; end
        fprintf('    %-12s L=%s R=%s%s\n', jc{1}, blank(dl), blank(dr), tag);
    end

    % ---- [4] non-physiological joint max/min per obstacle ----
    fprintf('\n[4] Joint max/min that look NON-PHYSIOLOGICAL (hand-calc candidates):\n');
    lim = struct('hip_flexion',100, 'knee_angle',135, 'ankle_angle',45);   % |deg| ceiling
    terrs = obstacleTerrains(S5);
    any4 = false;
    for jc = {'hip_flexion','knee_angle','ankle_angle'}
        th = lim.(jc{1});
        for s = {'l','r'}
            k = find(strcmp({Sg.signal.label}, sprintf('Joint: %s_%s', jc{1}, s{1})), 1);  if isempty(k), continue; end
            Y = Sg.signal(k).strides;
            if upper(s{1})=='R', T = S5.camera.terrainR; R = S5.camera.roleR; else, T = S5.camera.terrainL; R = S5.camera.roleL; end
            for tt = terrs
                mxv = []; mnv = []; rl = '';
                for j = 1:min(size(Y,2), numel(T))
                    if ~isempty(T{j}) && strcmp(T{j}, tt{1}) && ~isempty(R{j})
                        mxv(end+1) = max(Y(:,j)); mnv(end+1) = min(Y(:,j)); rl = R{j}; %#ok<AGROW>
                    end
                end
                if isempty(mxv), continue; end
                mm = mean(mxv,'omitnan');  mn = mean(mnv,'omitnan');
                if abs(mm) > th || abs(mn) > th
                    fprintf('    %-12s %-6s %-9s max=%6.0f  min=%6.0f   <-- check\n', jc{1}, tt{1}, rl, mm, mn);
                    any4 = true;
                end
            end
        end
    end
    if ~any4, fprintf('    (none flagged - joints look physiological)\n'); end
    fprintf('\nTip: put hand values for the flagged ones in Analysis/manualJointValues.m\n');
    fprintf('=======================================================\n');
end

% -------------------- helpers --------------------
function f = latest(dr, pat)
    f = '';  d = dir(fullfile(dr, pat));  if isempty(d), return; end
    [~,i] = max([d.datenum]);  f = fullfile(d(i).folder, d(i).name);
end

function E = readErr(f)
    E = struct();
    if isempty(f) || ~isfile(f), return; end
    L = readlines(f);  hi = find(contains(L,'endheader'), 1);  if isempty(hi), return; end
    hdr = split(strip(L(hi+1)), sprintf('\t'));
    M = readmatrix(f, 'FileType','text', 'NumHeaderLines', hi+1);
    for c = 2:min(numel(hdr), size(M,2))
        nm = erase(char(hdr(c)), '_imu');
        if isvarname(nm), E.(nm) = mean(M(:,c), 'omitnan')*180/pi; end
    end
end

function v = getf(s, f, dflt)
    if isstruct(s) && isfield(s, f), v = s.(f); else, v = dflt; end
end

function imus = jointIMUs(lbl)
    imus = {};  if endsWith(lbl,'_l'), sfx='_l'; elseif endsWith(lbl,'_r'), sfx='_r'; else, return; end
    base = lbl(1:end-2);
    if     startsWith(base,'hip'),     imus = {['femur' sfx]};
    elseif strcmp(base,'knee_angle'),  imus = {['femur' sfx], ['tibia' sfx]};
    elseif strcmp(base,'ankle_angle'), imus = {['tibia' sfx], ['calcn' sfx]};
    end
end

function d = sideDom(Sg, joint, s)
    d = '';  k = find(strcmp({Sg.signal.label}, sprintf('Joint: %s_%s', joint, s)), 1);  if isempty(k), return; end
    m = mean(Sg.signal(k).strides, 2, 'omitnan');  if all(isnan(m)), return; end
    ref = median(m(1:min(4,numel(m))), 'omitnan');
    if (max(m)-ref) >= (ref-min(m)), d = '+'; else, d = '-'; end
end

function b = blank(x), if isempty(x), b = '?'; else, b = x; end, end

function terrs = obstacleTerrains(S5)
    all = [S5.camera.terrainL, S5.camera.terrainR];
    all = all(~cellfun(@isempty, all));
    terrs = unique(all, 'stable');
    terrs = terrs(~strcmpi(terrs, 'Level_Walk'));
end
