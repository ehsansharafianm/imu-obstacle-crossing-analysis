function crossing_ml_environment(quick)
% CROSSING_ML_ENVIRONMENT  Can the walker measure the environment? Obstacle height, position and toe
% clearance estimated from the wearable IMUs alone, with the camera used only to train and score.
%
%   crossing_ml_environment          % full run
%   crossing_ml_environment(true)    % quick test (fewer trees, draws and bootstrap resamples)
%
% Same rows and rules as crossing_ml_matlab.m: obstacle crossings with include_ml = 1, leave-one-
% participant-out (LOPO), every fitted step on the nine training participants. Questions:
%   Q1  Which environment quantities can be estimated for a new person, and how accurately?
%         obstacle height (camera, measured per crossing), trailing foot placement before the
%         obstacle, leading landing distance after it, leading and trailing minimum toe clearance;
%         supplementary: leading / trailing toe peak height, trailing landing distance
%   Q2  Which sensors carry it: thigh, shank, foot IMU, thigh + shank, all three; leading, trailing
%       or both limbs?
%   Q3  Physics: the foot apex lies over the obstacle, so the foot path alone locates the obstacle;
%       the foot lift minus the obstacle height gives the clearance.
%   Q4  How much does a short labelled calibration (camera on 1 or 3 crossings of the new person)
%       add, and how does it compare with simply using that person's mean?
%   Q5  Does the estimate follow the crossing-to-crossing changes of one person (within cells), and
%       what is known before the trailing toe leaves the floor (leading limb only)?
% Inputs: the 110 Dot FEATURE columns + 13 clearance-shape features per limb + leg length, grouped by
% sensor site; normalisation generic (level walk, mm / leg length) or person scaling (own median /
% IQR, no labels); models ridge (lambda 10, z-scored) and random forest (TreeBagger regression).
% Outputs -> Results/ML Models/MATLAB/ml_environment_matlab.md, fig_environment.png,
% fig_environment_scatter.png (crossing_ml_figures, group 'environment')

if nargin < 1, quick = false; end
here = fileparts(mfilename('fullpath'));
root = fileparts(fileparts(here));
addpath(here);
out = fullfile(root, 'Results', 'ML Models', 'MATLAB');
if ~isfolder(out), mkdir(out); end
if isempty(gcp('nocreate')), parpool('Processes'); end
CFG.nTrees = ternary(quick, 50, 300);  CFG.nBoot = ternary(quick, 200, 2000);  CFG.nDraw = ternary(quick, 3, 20);
t0 = tic;

% ---------------- data ----------------
Dd = mlTools.load(root);  T = Dd.T;  F = Dd.feats;  mmF = strcmp(Dd.units, 'mm');
obs = T.is_level == 0 & T.include_ml == 1;
C = mlTools.loadCurvesBoth(root, T.crossing_id);
[SHl, pn] = mlTools.shapeFeats(C.lead);  SHt = mlTools.shapeFeats(C.trail);
mmS = startsWith(pn, {'x_', 'h_'});
names = [F, strcat({'lead_shape_'}, pn), strcat({'trail_shape_'}, pn)];
raw = [T{:, F}, SHl, SHt];  mm = [mmF, mmS, mmS];
Xlev = mlTools.calibrate(T, raw, mm);  Xlev = Xlev(obs, :);       % generic: level-walk offset, mm / leg length
d = T(obs, :);  g = d.participant_id;  P = unique(g)';
Xself = mlTools.selfnorm(raw(obs, :), g);                         % person scaling, no labels
LL = d.leg_length_cm;  cls = d.height_class;
key = strcat(cellstr(num2str(g)), '_', d.obstacle_code);

% ---------------- input sets: sensor site x limb ----------------
leadG = {'stride_len_app1','stride_len_app2','speed_approach','speed_cross','cadence'};
site = @(l, s) startsWith(names, [l '_' s '_']);
footOf = @(l) startsWith(names, [l '_foot_']) | startsWith(names, [l '_zhc_']) | startsWith(names, [l '_shape_']) | ...
    ismember(names, {[l '_swing_time'], [l '_stance_time']}) | (strcmp(l, 'lead') & ismember(names, leadG));
sensors = {'thigh', 'shank', 'foot', 'thigh + shank', 'thigh + shank + foot'};
limbs = {'lead', 'trail', 'both'};
SETS = struct('sensor', {}, 'limb', {}, 'name', {}, 'cols', {});
for s = 1:numel(sensors)
    for l = 1:numel(limbs)
        if strcmp(limbs{l}, 'both'), ll = {'lead', 'trail'}; else, ll = limbs(l); end
        m = false(size(names));
        for q = ll
            if contains(sensors{s}, 'thigh'), m = m | site(q{1}, 'thigh'); end
            if contains(sensors{s}, 'shank'), m = m | site(q{1}, 'shank'); end
            if contains(sensors{s}, 'foot'),  m = m | footOf(q{1}); end
        end
        if strcmp(limbs{l}, 'both') && contains(sensors{s}, 'foot'), m = m | strcmp(names, 'cross_duration'); end
        SETS(end+1) = struct('sensor', sensors{s}, 'limb', limbs{l}, 'name', sprintf('%s, %s', sensors{s}, limbs{l}), 'cols', find(m)); %#ok<AGROW>
    end
end
norms = {'level', 'generic (level walk)';  'self', 'person scaling'};
models = {'ridge', 'forest'};

% ---------------- targets (camera; never inputs) ----------------
TG = struct('key', {'height', 'trailplace', 'leadland', 'leadclear', 'trailclear', 'leadtoe', 'trailtoe', 'trailland'}, ...
    'col', {'cam_obstacle_h', 'trail_cam_takeoff_dist', 'lead_cam_landing_dist', 'lead_cam_min_clearance', 'trail_cam_min_clearance', ...
            'lead_cam_peak_foot_h', 'trail_cam_peak_foot_h', 'trail_cam_landing_dist'}, ...
    'label', {'obstacle height', 'trailing foot placement before the obstacle', 'leading landing distance after the obstacle', ...
              'leading minimum toe clearance', 'trailing minimum toe clearance', 'leading toe peak height', 'trailing toe peak height', ...
              'trailing landing distance after the obstacle'}, ...
    'short', {'obstacle height', 'trailing placement', 'leading landing', 'leading clearance', 'trailing clearance', ...
              'leading toe peak', 'trailing toe peak', 'trailing landing'}, ...
    'limb', {'both', 'trail', 'lead', 'lead', 'trail', 'lead', 'trail', 'trail'}, 'main', {true, true, true, true, true, false, false, false});
nT = numel(TG);
Y = cell2mat(arrayfun(@(t) d.(t.col), TG, 'UniformOutput', false));

% ---------------- Q1/Q2: LOPO grid (target x input set x normalisation x model) ----------------
XS = cell(numel(SETS), 2);
for s = 1:numel(SETS)
    XS{s, 1} = [Xlev(:, SETS(s).cols), LL];  XS{s, 2} = [Xself(:, SETS(s).cols), LL];
end
[jt, js, jn, jm] = ndgrid(1:nT, 1:numel(SETS), 1:2, 1:2);  J = [jt(:) js(:) jn(:) jm(:)];
PR = nan(size(Y, 1), size(J, 1));  nTrees = CFG.nTrees;
parfor j = 1:size(J, 1)
    PR(:, j) = lopoReg(XS{J(j,2), J(j,3)}, Y(:, J(j,1)), g, models{J(j,4)}, nTrees); %#ok<PFBNS>
end
fprintf('grid done (%d LOPO runs, %.0f s)\n', size(J, 1), toc(t0));
base = nan(size(Y));
for t = 1:nT
    for p = P, tr = g ~= p & isfinite(Y(:, t));  base(g == p, t) = mean(Y(tr, t)); end
end
G = struct();                                                     % metrics of every run
G.mae = nan(nT, numel(SETS), 2, 2);  G.r = G.mae;  G.rw = G.mae;  G.cal3 = G.mae;  G.cal1 = G.mae;
for j = 1:size(J, 1)
    t = J(j,1);  M = metr(Y(:, t), PR(:, j), key);
    G.mae(J(j,1), J(j,2), J(j,3), J(j,4)) = M.mae;  G.r(J(j,1), J(j,2), J(j,3), J(j,4)) = M.r;
    G.rw(J(j,1), J(j,2), J(j,3), J(j,4)) = M.rw;
    G.cal1(J(j,1), J(j,2), J(j,3), J(j,4)) = calib(Y(:, t), PR(:, j), g, cls, 1, CFG.nDraw);
    G.cal3(J(j,1), J(j,2), J(j,3), J(j,4)) = calib(Y(:, t), PR(:, j), g, cls, 3, CFG.nDraw);
end
G.rw(strcmp({TG.key}, 'height'), :, :, :) = NaN;                  % the height is constant within a participant x obstacle cell
B = struct('mae', nan(nT, 1), 'r', nan(nT, 1), 'own1', nan(nT, 1), 'own3', nan(nT, 1));
for t = 1:nT
    Mb = metr(Y(:, t), base(:, t), key);  B.mae(t) = Mb.mae;
    [~, B.own1(t)] = calib(Y(:, t), base(:, t), g, cls, 1, CFG.nDraw);
    [~, B.own3(t)] = calib(Y(:, t), base(:, t), g, cls, 3, CFG.nDraw);
end

% ---------------- Q3: physics estimators (foot path only; offset and slope learned on 9 people) ----------------
lift = @(l) d.([l '_zhc_peak_foot_h']);
PH = struct('target', {}, 'name', {}, 'x', {}, 'needsH', {});
PH(end+1) = struct('target', 'height', 'name', 'leading + trailing foot lift', 'x', [lift('lead'), lift('trail')], 'needsH', 0);
PH(end+1) = struct('target', 'trailplace', 'name', 'trailing foot apex position (progression to the peak)', 'x', d.trail_zhc_peak_h_x, 'needsH', 0);
PH(end+1) = struct('target', 'leadland', 'name', 'leading progression from the apex to landing', 'x', d.lead_zhc_x_landing - d.lead_zhc_peak_h_x, 'needsH', 0);
PH(end+1) = struct('target', 'trailland', 'name', 'trailing progression from the apex to landing', 'x', d.trail_zhc_x_landing - d.trail_zhc_peak_h_x, 'needsH', 0);
PH(end+1) = struct('target', 'leadtoe', 'name', 'leading foot lift', 'x', lift('lead'), 'needsH', 0);
PH(end+1) = struct('target', 'trailtoe', 'name', 'trailing foot lift', 'x', lift('trail'), 'needsH', 0);
PH(end+1) = struct('target', 'leadclear', 'name', 'leading foot lift - estimated obstacle height', 'x', lift('lead'), 'needsH', 1);
PH(end+1) = struct('target', 'trailclear', 'name', 'trailing foot lift - estimated obstacle height', 'x', lift('trail'), 'needsH', 1);
PH(end+1) = struct('target', 'leadclear', 'name', 'leading foot lift - TRUE obstacle height (reference)', 'x', lift('lead'), 'needsH', 2);
PH(end+1) = struct('target', 'trailclear', 'name', 'trailing foot lift - TRUE obstacle height (reference)', 'x', lift('trail'), 'needsH', 2);
Hx = [lift('lead'), lift('trail')];  yH = d.cam_obstacle_h;
for k = 1:numel(PH)
    t = strcmp({TG.key}, PH(k).target);  y = Y(:, t);  pr = nan(size(y));
    for p = P
        tr = g ~= p;  te = g == p;
        X = PH(k).x;
        if PH(k).needsH == 1                                      % nested: obstacle height estimated without the test person
            Htr = nan(size(y));
            for q = P(P ~= p)
                i2 = tr & g ~= q;  Htr(g == q) = olsPred(Hx(i2, :), yH(i2), Hx(g == q, :));
            end
            Htr(te) = olsPred(Hx(tr, :), yH(tr), Hx(te, :));
            X = [X, Htr]; %#ok<AGROW>
        elseif PH(k).needsH == 2
            X = [X, yH]; %#ok<AGROW>
        end
        pr(te) = olsPred(X(tr, :), y(tr), X(te, :));
    end
    M = metr(y, pr, key);
    if strcmp(PH(k).target, 'height'), M.rw = NaN; end
    PH(k).mae = M.mae;  PH(k).r = M.r;  PH(k).rw = M.rw;  PH(k).r2 = M.r2;  PH(k).pred = pr;
    PH(k).cal3 = calib(y, pr, g, cls, 3, CFG.nDraw);
end
fprintf('physics done (%.0f s)\n', toc(t0));

% ---------------- best estimates, participant-bootstrap CI, Bland-Altman ----------------
BEST = struct('key', {TG.key});
for t = 1:nT
    [BEST(t).noLab, BEST(t).noLabIdx] = bestOf(squeeze(G.mae(t, :, :, :)));
    [BEST(t).lab3, BEST(t).lab3Idx] = bestOf(squeeze(G.cal3(t, :, :, :)));
    [BEST(t).leadOnly, BEST(t).leadOnlyIdx] = bestOf(squeeze(G.mae(t, strcmp({SETS.limb}, 'lead'), :, :)));
    li = find(strcmp({SETS.limb}, 'lead'));  BEST(t).leadOnlyIdx(1) = li(BEST(t).leadOnlyIdx(1));
    i = BEST(t).noLabIdx;  j = J(:,1) == t & J(:,2) == i(1) & J(:,3) == i(2) & J(:,4) == i(3);
    y = Y(:, t);  pr = PR(:, j);  ok = isfinite(y) & isfinite(pr);
    BEST(t).pred = pr;  BEST(t).ci = bootMae(y, pr, g, CFG.nBoot);
    BEST(t).bias = mean(pr(ok) - y(ok));  BEST(t).loa = 1.96 * std(pr(ok) - y(ok));
    BEST(t).r = G.r(t, i(1), i(2), i(3));  BEST(t).rw = G.rw(t, i(1), i(2), i(3));
    BEST(t).r2 = 1 - sum((y(ok) - pr(ok)).^2) / sum((y(ok) - mean(y(ok))).^2);
    BEST(t).ciBase = bootMae(y, base(:, t), g, CFG.nBoot);
end

iDev = find(strcmp({SETS.sensor}, 'foot') & strcmp({SETS.limb}, 'both'));
DEV = struct('mae', G.mae(:, iDev, 2, 2), 'rw', G.rw(:, iDev, 2, 2), 'r', G.r(:, iDev, 2, 2), 'cal3', G.cal3(:, iDev, 2, 2));
% Q3b: height or margin? The device reads the height from the foot lift, so a crossing lifted higher than usual looks like
% a higher obstacle: the height error should follow the clearance (one measurement, two unknowns).
eH = BEST(1).pred - Y(:, 1);  ID = struct('name', {}, 'r', {}, 'rp', {});
for t = find(ismember({TG.key}, {'leadclear', 'trailclear'}))
    ok = isfinite(eH) & isfinite(Y(:, t));  ec = eH;  yc = Y(:, t);
    for p = P, i = g == p & ok; ec(i) = eH(i) - mean(eH(i)); yc(i) = Y(i, t) - mean(Y(i, t)); end
    ID(end+1) = struct('name', TG(t).label, 'r', corr(eH(ok), Y(ok, t)), 'rp', corr(ec(ok), yc(ok))); %#ok<AGROW>
end

% ---------------- report ----------------
L = {};
L = addl(L, '# Can the walker measure the environment? (MATLAB)');
L = addl(L, '');
L = addl(L, '_Generated by `Analysis/ML/crossing_ml_environment.m` on %s, MATLAB %s._%s', char(datetime('now', 'Format', 'yyyy-MM-dd HH:mm')), ...
    version('-release'), ternary(quick, ' **QUICK TEST RUN.**', ''));
L = addl(L, '');
L = addl(L, ['%d obstacle crossings (include_ml), 10 participants. Every estimate is for a participant left out of training (LOPO). The camera gives ' ...
    'the targets (training and scoring only); the inputs are the Dot IMUs. Inputs per limb and sensor site: thigh / shank = tilt and angular-velocity ' ...
    'summaries; foot = foot tilt, angular velocity and acceleration, the foot trajectory (ZHC) summaries, the 13 clearance-shape features, swing and ' ...
    'stance time (+ the approach strides for the leading foot); leg length is added to every set. Normalisation: **generic** = minus the person''s ' ...
    'level-walk median, lengths / leg length; **person** = (x - own median) / own IQR over the person''s obstacle crossings (no labels). Models: ridge ' ...
    '(lambda 10, z-scored) and random forest (%d trees, min leaf 3). Metrics: mean absolute error (MAE), Pearson r, and r **within cells** (target and ' ...
    'estimate minus their participant x obstacle means: does the estimate follow the crossing-to-crossing changes?). Baseline = the training ' ...
    'participants'' mean. **Calibration** = a few camera-labelled crossings of the new person (1, or 3 = one per height; %d random draws) shift ' ...
    'the estimate by its mean error on them; compared with simply using the mean of those labelled crossings (own mean).'], nnz(obs), CFG.nTrees, CFG.nDraw);
L = addl(L, '');
L = addl(L, '## E1. The targets');
L = addl(L, '');
L = addl(L, '| target | camera column | n | mean (mm) | SD (mm) | baseline MAE (mm) | own mean of 1 / 3 labelled crossings: MAE (mm) |');
L = addl(L, '|---|---|---|---|---|---|---|');
for t = 1:nT
    y = Y(:, t);
    L = addl(L, '| %s | `%s` | %d | %.0f | %.0f | %.0f | %.0f / %.0f |', TG(t).label, TG(t).col, nnz(isfinite(y)), mean(y, 'omitnan'), ...
        std(y, 'omitnan'), B.mae(t), B.own1(t), B.own3(t));
end
L = addl(L, '');
L = addl(L, ['Definitions (camera, marker centres): obstacle height = obstacle-marker top per crossing; trailing foot placement = near edge - trailing ' ...
    'toe at its foot-flat before the obstacle; leading landing = leading heel at its foot-flat after the obstacle - far edge; trailing landing = ' ...
    'the same for the trailing heel; minimum clearance = lowest toe / heel marker over the obstacle footprint - obstacle top; toe peak = highest toe ' ...
    'marker in the stride above the floor.']);
L = addl(L, '');
% summary
L = addl(L, '## E2. Summary: best estimate per target');
L = addl(L, '');
L = addl(L, ['Best of the grid (5 sensor sets x 3 limb choices x 2 normalisations x 2 models; a small selection optimism remains). Without labels: ' ...
    'MAE with participant-bootstrap 95%% CI (%d resamples), r, R^2, r within cells, Bland-Altman bias and 95%% limits (+-). With 3 labelled ' ...
    'crossings: best calibrated estimate vs the own mean of the same 3 crossings.'], CFG.nBoot);
L = addl(L, '');
L = addl(L, '| target | baseline MAE | best without labels (inputs) | MAE (95% CI) | r | R^2 | r within cells | bias +- LoA | 3 labelled: best (inputs) | 3 labelled: own mean |');
L = addl(L, '|---|---|---|---|---|---|---|---|---|---|');
for t = 1:nT
    b = BEST(t);
    L = addl(L, '| %s | %.0f mm | %s | %.0f mm (%.0f-%.0f) | %.2f | %.2f | %.2f | %+.0f +- %.0f mm | %.0f mm (%s) | %.0f mm |', TG(t).label, B.mae(t), ...
        runName(SETS, norms, models, b.noLabIdx), b.noLab, b.ci(1), b.ci(2), b.r, b.r2, b.rw, b.bias, b.loa, b.lab3, ...
        runName(SETS, norms, models, b.lab3Idx), B.own3(t));
end
L = addl(L, '');
L = addl(L, ['The obstacle height is constant within a cell, so its within-cell r is not defined (-); for the height the own mean of 3 labelled ' ...
    'crossings (one per height) is not a sensible reference.']);
L = addl(L, '');
L = addl(L, '**Fixed device model** (chosen in advance, no selection: two foot IMUs, both limbs, person scaling, random forest):');
L = addl(L, '');
L = addl(L, '| target | baseline MAE | MAE | r | r within cells | MAE with 3 labelled |');
L = addl(L, '|---|---|---|---|---|---|');
for t = 1:nT
    L = addl(L, '| %s | %.0f mm | %.0f mm | %.2f | %.2f | %.0f mm |', TG(t).label, B.mae(t), DEV.mae(t), DEV.r(t), DEV.rw(t), DEV.cal3(t));
end
L = addl(L, '');
% physics
L = addl(L, '## E3. Physics estimators from the foot path alone');
L = addl(L, '');
L = addl(L, ['Ordinary least squares on one or two foot-trajectory quantities, offset and slope learned on the nine training participants. The obstacle ' ...
    'position follows from the apex: people lift the foot highest roughly over the obstacle, so the progression to the apex (trailing foot) or ' ...
    'from the apex to landing (leading foot) locates the obstacle. Obstacle width is not used (the device does not know it). For the clearance, ' ...
    'the obstacle height is estimated from the foot lifts inside the training participants (nested); the TRUE-height rows show the limit if the device were told the height.']);
L = addl(L, '');
L = addl(L, '| target | estimator | MAE (mm) | baseline MAE (mm) | r | R^2 | r within cells | MAE with 3 labelled (mm) |');
L = addl(L, '|---|---|---|---|---|---|---|---|');
for k = 1:numel(PH)
    t = strcmp({TG.key}, PH(k).target);
    L = addl(L, '| %s | %s | %.0f | %.0f | %.2f | %.2f | %.2f | %.0f |', TG(t).label, PH(k).name, PH(k).mae, B.mae(t), PH(k).r, PH(k).r2, PH(k).rw, PH(k).cal3);
end
L = addl(L, '');
% sensors (both limbs) and limbs (all sensors)
L = addl(L, '## E4. Which sensors? (both limbs; best normalisation and model per cell, no labels)');
L = addl(L, '');
L = addl(L, ['Cell = MAE in mm (r within cells); bold = best sensor set for the target. Baseline = training mean. The best normalisation / model per ' ...
    'cell is chosen on the result (as in E2).']);
L = addl(L, '');
L = addl(L, ['| target | baseline | ' strjoin(sensors, ' | ') ' |']);
L = addl(L, ['|---|---|' repmat('---|', 1, numel(sensors))]);
for t = 1:nT
    c = cell(1, numel(sensors));  v = nan(1, numel(sensors));
    for s = 1:numel(sensors)
        i = find(strcmp({SETS.sensor}, sensors{s}) & strcmp({SETS.limb}, 'both'));
        [v(s), ix] = bestNM(G.mae(t, i, :, :));  c{s} = sprintf('%.0f (%.2f)', v(s), G.rw(t, i, ix(1), ix(2)));
    end
    [~, b] = min(v);  c{b} = ['**' c{b} '**'];
    L = addl(L, '| %s | %.0f | %s |', TG(t).label, B.mae(t), strjoin(c, ' | '));
end
L = addl(L, '');
L = addl(L, '## E5. Which limb? (all three sensors; best normalisation and model per cell, no labels)');
L = addl(L, '');
L = addl(L, 'Cell = MAE in mm (r within cells). The leading limb alone is what a device knows before the trailing toe leaves the floor.');
L = addl(L, '');
L = addl(L, '| target | baseline | leading limb | trailing limb | both limbs |');
L = addl(L, '|---|---|---|---|---|');
for t = 1:nT
    c = cell(1, 3);
    for l = 1:3
        i = find(strcmp({SETS.sensor}, sensors{end}) & strcmp({SETS.limb}, limbs{l}));
        [v, ix] = bestNM(G.mae(t, i, :, :));  c{l} = sprintf('%.0f (%.2f)', v, G.rw(t, i, ix(1), ix(2)));
    end
    L = addl(L, '| %s | %.0f | %s |', TG(t).label, B.mae(t), strjoin(c, ' | '));
end
L = addl(L, '');
L = addl(L, '## E6. Generic vs person scaling vs a short labelled calibration (all three sensors, both limbs; random forest)');
L = addl(L, '');
L = addl(L, 'MAE in mm. Calibration shifts the estimate by its mean error on the labelled crossings; own mean = the mean of the same labelled crossings.');
L = addl(L, '');
L = addl(L, '| target | baseline | generic | person scaling | generic + 1 labelled | person + 1 labelled | generic + 3 labelled | person + 3 labelled | own mean of 3 |');
L = addl(L, '|---|---|---|---|---|---|---|---|---|');
iA = find(strcmp({SETS.sensor}, sensors{end}) & strcmp({SETS.limb}, 'both'));
for t = 1:nT
    L = addl(L, '| %s | %.0f | %.0f | %.0f | %.0f | %.0f | %.0f | %.0f | %.0f |', TG(t).label, B.mae(t), G.mae(t, iA, 1, 2), G.mae(t, iA, 2, 2), ...
        G.cal1(t, iA, 1, 2), G.cal1(t, iA, 2, 2), G.cal3(t, iA, 1, 2), G.cal3(t, iA, 2, 2), B.own3(t));
end
L = addl(L, '');
L = addl(L, '## E7. Height or margin? One measurement, two unknowns');
L = addl(L, '');
L = addl(L, ['The foot lift is the obstacle height plus the person''s margin. A device that reads the height from the foot lift therefore ' ...
    'mistakes a larger margin for a higher obstacle: the error of the best height estimate (estimate - camera) should rise with the clearance. ' ...
    'r overall and after removing each participant''s mean:']);
L = addl(L, '');
L = addl(L, '| clearance | r with the height error | r within participants |');
L = addl(L, '|---|---|---|');
for k = 1:numel(ID), L = addl(L, '| %s | %+.2f | %+.2f |', ID(k).name, ID(k).r, ID(k).rp); end
L = addl(L, '');
L = addl(L, '## E8. Every run');
L = addl(L, '');
L = addl(L, 'MAE in mm (r) for each target, input set, normalisation and model; no labels.');
for t = 1:nT
    L = addl(L, '');
    L = addl(L, '**%s** (baseline %.0f mm)', TG(t).label, B.mae(t));
    L = addl(L, '');
    L = addl(L, '| inputs | generic, ridge | generic, forest | person, ridge | person, forest |');
    L = addl(L, '|---|---|---|---|---|');
    for s = 1:numel(SETS)
        c = arrayfun(@(q) sprintf('%.0f (%.2f)', G.mae(t, s, 1 + (q > 2), 2 - mod(q, 2)), G.r(t, s, 1 + (q > 2), 2 - mod(q, 2))), 1:4, 'UniformOutput', false);
        L = addl(L, '| %s | %s |', SETS(s).name, strjoin(c, ' | '));
    end
end
L = addl(L, '');
% reading
h = BEST(1);  tp = BEST(2);  ld = BEST(3);  lc = BEST(4);  tc = BEST(5);
phTp = PH(strcmp({PH.target}, 'trailplace'));  phLc = PH(strcmp({PH.target}, 'leadclear') & [PH.needsH] == 1);
phTc = PH(strcmp({PH.target}, 'trailclear') & [PH.needsH] == 1);
L = addl(L, '## Reading');
L = addl(L, '');
L = addl(L, ['- **Height: yes.** The obstacle height is estimated for a new person with %.0f mm MAE (r = %.2f; baseline %.0f mm), and with %.0f mm from ' ...
    'the leading limb alone, i.e. before the trailing foot crosses.'], h.noLab, h.r, B.mae(1), h.leadOnly);
L = addl(L, ['- **Position: yes, from the trailing foot.** The trailing foot placement before the obstacle is estimated with %.0f mm MAE (r = %.2f, ' ...
    'within cells %.2f; baseline %.0f mm); the physics estimator (trailing apex position alone) gives %.0f mm (within cells %.2f). The leading ' ...
    'landing distance is harder: %.0f mm (r = %.2f; baseline %.0f mm).'], tp.noLab, tp.r, tp.rw, B.mae(2), phTp.mae, phTp.rw, ld.noLab, ld.r, B.mae(3));
L = addl(L, ['- **Clearance: partly.** Leading %.0f mm (r = %.2f; baseline %.0f), trailing %.0f mm (r = %.2f; baseline %.0f) without labels; ' ...
    'foot lift minus the estimated height gives %.0f / %.0f mm. With 3 labelled crossings: %.0f / %.0f mm, against %.0f / %.0f mm for the ' ...
    'own mean of the same crossings.'], lc.noLab, lc.r, B.mae(4), tc.noLab, tc.r, B.mae(5), phLc.mae, phTc.mae, lc.lab3, tc.lab3, B.own3(4), B.own3(5));
L = addl(L, ['- **Why the clearance is hard:** the height error of the device rises with the clearance (r = %+.2f leading, %+.2f trailing): ' ...
    'the foot lift contains height and margin together, so reading one from it hides the other; only a known height (or another ' ...
    'source of it) frees the foot lift to measure the margin.'], ID(1).r, ID(2).r);
L = strrep(L, '| NaN', '| -');  L = strrep(L, '(NaN)', '(-)');
writeLines(fullfile(out, 'ml_environment_matlab.md'), L);

% ---------------- figures ----------------
S = struct('TG', {rmfield(TG, {'col'})}, 'sensors', {sensors}, 'limbs', {limbs}, 'setSensor', {{SETS.sensor}}, 'setLimb', {{SETS.limb}}, ...
    'mae', G.mae, 'rw', G.rw, 'cal3', G.cal3, 'base', B.mae, 'own3', B.own3, 'Y', Y, 'g', g, 'cls', {cls}, ...
    'bestPred', [BEST.pred], 'bestNoLab', [BEST.noLab], 'bestR', [BEST.r], 'bestRw', [BEST.rw], 'bestName', ...
    {arrayfun(@(b) runName(SETS, norms, models, b.noLabIdx), BEST, 'UniformOutput', false)}, 'phPlace', phTp.pred, 'devMae', DEV.mae, 'phys', {rmfield(PH, {'x', 'pred'})}, 'ident', {ID});
mlTools.figures(out, 'environment', S);
fprintf('Wrote %s (%.0f s)\n', fullfile(out, 'ml_environment_matlab.md'), toc(t0));
end

%% ========================================================================
function p = lopoReg(X, y, g, mdl, nTrees)
% LOPO predictions; rows with a missing target are not trained on (but are predicted).
p = nan(size(y));
for q = unique(g)'
    tr = g ~= q & isfinite(y);  te = g == q;
    p(te) = regFit(X(tr, :), y(tr), X(te, :), mdl, nTrees);
end
end

function yp = regFit(Xtr, ytr, Xte, mdl, nTrees)
% Ridge (lambda 10 on z-scored features) or random-forest regression; median imputation from the training rows.
med = median(Xtr, 1, 'omitnan');  med(isnan(med)) = 0;
Xtr = mlTools.fillMed(Xtr, med);  Xte = mlTools.fillMed(Xte, med);
mu = mean(Xtr, 1);  sd = std(Xtr, 0, 1);  sd(sd == 0) = 1;
Ztr = (Xtr - mu) ./ sd;  Zte = (Xte - mu) ./ sd;
if strcmp(mdl, 'ridge')
    A = [ones(size(Ztr, 1), 1) Ztr];  Rg = 10 * eye(size(A, 2));  Rg(1, 1) = 0;
    b = (A' * A + Rg) \ (A' * ytr);  yp = [ones(size(Zte, 1), 1) Zte] * b;
else
    rng(0);  M = TreeBagger(nTrees, Ztr, ytr, 'Method', 'regression', 'MinLeafSize', 3);  yp = predict(M, Zte);
end
end

function yp = olsPred(Xtr, ytr, Xte)
ok = all(isfinite(Xtr), 2) & isfinite(ytr);
b = [ones(nnz(ok), 1) Xtr(ok, :)] \ ytr(ok);
yp = [ones(size(Xte, 1), 1) Xte] * b;
end

function M = metr(y, p, key)
% MAE, r, R^2 and r within participant x obstacle cells (both minus their cell means).
ok = isfinite(y) & isfinite(p);  y = y(ok);  p = p(ok);  key = key(ok);
M.mae = mean(abs(p - y));  M.r = corr(p, y);  M.r2 = 1 - sum((y - p).^2) / sum((y - mean(y)).^2);
[~, ~, j] = unique(key);  yc = y;  pc = p;
for k = 1:max(j), i = j == k; yc(i) = y(i) - mean(y(i)); pc(i) = p(i) - mean(p(i)); end
M.rw = corr(pc, yc);
end

function [maeCal, maeOwn] = calib(y, p, g, cls, k, nDraw)
% k camera-labelled crossings per new person (k = 3: one per height): shift the estimate by its mean
% error on them (maeCal); or use the mean of the labelled targets (maeOwn). Scored on the other crossings.
e1 = [];  e2 = [];
for r = 1:nDraw
    rs = RandStream('mt19937ar', 'Seed', 100 * k + r);
    for q = unique(g)'
        i = find(g == q & isfinite(y) & isfinite(p));
        if k == 3
            c = arrayfun(@(h) pick(rs, i(strcmp(cls(i), sprintf('H%d', h)))), 1:3);  c = c(isfinite(c));
        else
            c = i(randi(rs, numel(i)));
        end
        rest = setdiff(i, c);
        e1 = [e1; abs(p(rest) + mean(y(c) - p(c)) - y(rest))]; %#ok<AGROW>
        e2 = [e2; abs(mean(y(c)) - y(rest))]; %#ok<AGROW>
    end
end
maeCal = mean(e1);  maeOwn = mean(e2);
end

function c = pick(rs, i)
if isempty(i), c = NaN; else, c = i(randi(rs, numel(i))); end
end

function [v, idx] = bestOf(A)
% Minimum over a (set x norm x model) block; idx = [set norm model].
[v, k] = min(A(:));  [a, b, c] = ind2sub(size(A), k);  idx = [a b c];
end

function [v, idx] = bestNM(A)
% Minimum over the normalisation x model block of one target and input set; idx = [norm model].
A = reshape(A, 2, 2);  [v, k] = min(A(:));  [a, b] = ind2sub([2 2], k);  idx = [a b];
end

function s = runName(SETS, norms, models, idx)
s = sprintf('%s; %s, %s', SETS(idx(1)).name, strrep(norms{idx(2), 2}, ' (level walk)', ''), models{idx(3)});
end

function ci = bootMae(y, p, g, nBoot)
rs = RandStream('mt19937ar', 'Seed', 0);  P = unique(g);  a = nan(nBoot, 1);
idx = arrayfun(@(q) find(g == q & isfinite(y) & isfinite(p)), P, 'UniformOutput', false);
for b = 1:nBoot
    i = vertcat(idx{randi(rs, numel(P), numel(P), 1)});  a(b) = mean(abs(p(i) - y(i)));
end
ci = prctile(a, [2.5 97.5]);
end

function L = addl(L, fmt, varargin)
if isempty(varargin), L{end+1} = strrep(fmt, '%%', '%'); else, L{end+1} = sprintf(fmt, varargin{:}); end
end

function v = ternary(c, a, b)
if c, v = a; else, v = b; end
end

function writeLines(f, L)
fid = fopen(f, 'w', 'n', 'UTF-8');  assert(fid > 0, 'cannot open %s', f);
c = onCleanup(@() fclose(fid));
fprintf(fid, '%s\n', L{:});
end
