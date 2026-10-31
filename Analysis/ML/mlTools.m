classdef mlTools
% MLTOOLS  Shared building blocks for the MATLAB port of the crossing ML analyses.
%
%   Used by crossing_ml_matlab.m. Mirrors Analysis/ML/python/crossing_ml*.py:
%   data loading (FEATURE columns from data_dictionary.md), level-walk and self
%   normalization, the model pipelines and leave-one-participant-out (LOPO) evaluation.
%
%   Pipelines (every fitted step uses the training rows only):
%     logreg : median imputation -> z-score -> [ANOVA-F top-k] -> L2 logistic regression
%              (objective C*sum(loss) + 0.5*||W||^2, intercept not penalized; softmax for
%              >= 3 classes, sigmoid for 2 - the scikit-learn lbfgs objective)
%     forest : median imputation -> TreeBagger (MinLeafSize 2, sqrt(p) predictors per split,
%              uniform class prior ~ class_weight 'balanced')
%     svm    : median imputation -> z-score -> RBF SVM (ECOC one-vs-one, kernel scale 'auto')
%     boost  : median imputation -> boosted shallow trees (AdaBoostM2; GentleBoost for 2 classes)
%     (svm / boost scores are turned into class probabilities with a softmax)

    methods (Static)

        %% ---------------- data ----------------
        function D = load(root)
            % Dataset + FEATURE list (dictionary order) + units.
            f = fullfile(root, 'Results', 'ML Dataset', 'Crossing_Master_YoungAdults.csv');
            o = detectImportOptions(f);
            txt = {'crossing_id','obstacle_code','height_class','width_class','order_randomized', ...
                   'leading_limb','sex','dominant_leg','cleaned_variables','role_imu'};
            o = setvartype(o, intersect(txt, o.VariableNames), 'char');
            T = readtable(f, o);
            for v = intersect(txt, T.Properties.VariableNames)
                T.(v{1})(cellfun(@isempty, T.(v{1}))) = {''};
            end
            L = splitlines(fileread(fullfile(root, 'Results', 'ML Dataset', 'data_dictionary.md')));
            feats = {};  units = {};
            for i = 1:numel(L)
                t = regexp(L{i}, '^\| \d+ \| `([^`]+)` \| ([^|]+) \| ([^|]+) \|', 'tokens', 'once');
                if isempty(t) || ~strcmp(strtrim(t{2}), 'FEATURE') || ~ismember(t{1}, T.Properties.VariableNames), continue; end
                x = T.(t{1});
                if endsWith(t{1}, '_zhc_peak_toe_h') || ~isnumeric(x) || all(isnan(x)), continue; end
                feats{end+1} = t{1};  units{end+1} = strtrim(t{3}); %#ok<AGROW>
            end
            D = struct('T', T, 'feats', {feats}, 'units', {units}, 'root', root);
        end

        function X = calibrate(T, X, mmCols)
            % Minus the participant's level-walk median (level & include_biomech); mm columns / leg length (mm).
            p = T.participant_id;
            for q = unique(p)'
                i = p == q;
                lv = i & T.is_level == 1 & T.include_biomech == 1;
                X(i,:) = X(i,:) - median(X(lv,:), 1, 'omitnan');
                ll = T.leg_length_cm(find(i, 1)) * 10;
                X(i, mmCols) = X(i, mmCols) / ll;
            end
        end

        function X = selfnorm(X, g)
            % Each participant: (x - own median) / own IQR (linear-interpolation quantiles); labels not used.
            for q = unique(g)'
                i = g == q;
                [med, iqr] = mlTools.medIqr(X(i,:));
                X(i,:) = (X(i,:) - med) ./ iqr;
            end
        end

        function [med, iqr] = medIqr(X)
            med = median(X, 1, 'omitnan');
            iqr = mlTools.q7(X, 0.75) - mlTools.q7(X, 0.25);
            iqr(iqr == 0 | isnan(iqr)) = 1;
        end

        function q = q7(X, p)
            % Quantile per column, linear interpolation (type 7, as numpy / pandas), NaN ignored.
            q = nan(1, size(X,2));
            for j = 1:size(X,2)
                v = sort(X(isfinite(X(:,j)), j));  n = numel(v);
                if n == 0, continue; end
                h = (n - 1) * p + 1;  lo = floor(h);  hi = min(lo + 1, n);
                q(j) = v(lo) + (h - lo) * (v(hi) - v(lo));
            end
        end

        function S = featureSets(feats)
            % all / lead only / trail only, then each group x (both, lead, trail).
            leadG = {'stride_len_app1','stride_len_app2','speed_approach','speed_cross','cadence'};
            isLead  = startsWith(feats, 'lead_') | ismember(feats, leadG);
            isTrail = startsWith(feats, 'trail_');
            G = {'thigh','_thigh_'; 'shank','_shank_'; 'foot angle','_foot_(?!acc)'; 'foot acc','_foot_acc_'; ...
                 'ZHC trajectory','_zhc_'; 'spatiotemporal','swing_time|stance_time|stride_len|speed|cadence|cross_duration'};
            S = struct('name', {'all','lead only','trail only'}, 'cols', {feats, feats(isLead), feats(isTrail)});
            for k = 1:size(G,1)
                m = ~cellfun(@isempty, regexp(feats, G{k,2}, 'once'));
                S(end+1) = struct('name', G{k,1}, 'cols', {feats(m)}); %#ok<AGROW>
                if any(m & isLead),  S(end+1) = struct('name', [G{k,1} ' (lead)'],  'cols', {feats(m & isLead)});  end %#ok<AGROW>
                if any(m & isTrail), S(end+1) = struct('name', [G{k,1} ' (trail)'], 'cols', {feats(m & isTrail)}); end %#ok<AGROW>
            end
        end

        function c = getSet(S, name)
            c = S(strcmp({S.name}, name)).cols;
        end

        %% ---------------- models ----------------
        function s = spec(kind, varargin)
            % spec('logreg', 'C', 0.1, 'k', 0) | spec('forest', 'nTrees', 500) | spec('svm') | spec('boost')
            s = struct('kind', kind, 'C', 0.1, 'k', 0, 'nTrees', 500, 'seed', 0);
            for i = 1:2:numel(varargin), s.(varargin{i}) = varargin{i+1}; end
        end

        function P = fitPipe(s, X, y, w)
            if nargin < 4 || isempty(w), w = ones(size(X,1), 1); end
            P = struct('s', s, 'classes', {unique(y)}, 'med', [], 'mu', [], 'sd', [], 'sel', [], 'W', [], 'b', [], 'tb', []);
            med = median(X, 1, 'omitnan');  med(isnan(med)) = 0;  P.med = med;
            X = mlTools.fillMed(X, med);
            [~, yi] = ismember(y, P.classes);
            switch s.kind
                case 'logreg'
                    P.mu = mean(X, 1);  sd = std(X, 1, 1);  sd(sd == 0) = 1;  P.sd = sd;
                    X = (X - P.mu) ./ sd;
                    P.sel = 1:size(X,2);
                    if s.k > 0
                        F = mlTools.anovaF(X, yi);  F(~isfinite(F)) = -inf;
                        [~, o] = sort(F, 'descend');  P.sel = sort(o(1:min(s.k, numel(o))));
                    end
                    [P.W, P.b] = mlTools.logregFit(X(:, P.sel), yi, numel(P.classes), s.C, w);
                case 'forest'
                    rng(s.seed, 'twister');
                    P.tb = TreeBagger(s.nTrees, X, y, 'Method', 'classification', 'MinLeafSize', 2, ...
                        'NumPredictorsToSample', max(1, floor(sqrt(size(X,2)))), 'Prior', 'Uniform', ...
                        'Options', statset('UseParallel', false));
                case 'svm'
                    P.mu = mean(X, 1);  sd = std(X, 0, 1);  sd(sd == 0) = 1;  P.sd = sd;
                    rng(s.seed, 'twister');
                    P.tb = fitcecoc((X - P.mu) ./ sd, y, 'Learners', templateSVM('KernelFunction', 'gaussian', ...
                        'KernelScale', 'auto', 'BoxConstraint', 1));
                case 'boost'
                    rng(s.seed, 'twister');
                    meth = 'AdaBoostM2';  if numel(P.classes) == 2, meth = 'GentleBoost'; end
                    P.tb = fitcensemble(X, y, 'Method', meth, 'NumLearningCycles', 200, ...
                        'Learners', templateTree('MaxNumSplits', 8), 'LearnRate', 0.1);
            end
        end

        function Pr = predictPipe(P, X)
            X = mlTools.fillMed(X, P.med);
            switch P.s.kind
                case 'logreg'
                    X = (X - P.mu) ./ P.sd;
                    Z = X(:, P.sel) * P.W + P.b;
                    if numel(P.classes) == 2
                        p1 = 1 ./ (1 + exp(-Z));  Pr = [1 - p1, p1];
                    else
                        Z = Z - max(Z, [], 2);  E = exp(Z);  Pr = E ./ sum(E, 2);
                    end
                case 'forest'
                    [~, sc] = predict(P.tb, X);
                    [~, j] = ismember(P.classes, P.tb.ClassNames);
                    Pr = sc(:, j);
                case {'svm', 'boost'}
                    if strcmp(P.s.kind, 'svm'), X = (X - P.mu) ./ P.sd; end
                    [~, sc] = predict(P.tb, X);
                    [~, j] = ismember(P.classes, P.tb.ClassNames);
                    sc = sc(:, j);  sc = exp(sc - max(sc, [], 2));
                    Pr = sc ./ sum(sc, 2);
            end
        end

        function X = fillMed(X, med)
            [r, c] = find(isnan(X));
            X(sub2ind(size(X), r, c)) = med(c);
        end

        function F = anovaF(X, yi)
            % One-way ANOVA F per column (scikit-learn f_classif).
            K = max(yi);  n = size(X,1);
            m = mean(X, 1);  ssb = zeros(1, size(X,2));  ssw = zeros(1, size(X,2));
            for k = 1:K
                Xk = X(yi == k, :);
                ssb = ssb + size(Xk,1) * (mean(Xk, 1) - m).^2;
                ssw = ssw + sum((Xk - mean(Xk, 1)).^2, 1);
            end
            F = (ssb / (K - 1)) ./ (ssw / (n - K));
        end

        function [W, b] = logregFit(X, yi, K, C, w)
            [n, p] = size(X);
            opts = optimoptions('fminunc', 'Algorithm', 'quasi-newton', 'SpecifyObjectiveGradient', true, ...
                'Display', 'off', 'MaxIterations', 3000, 'MaxFunctionEvaluations', 1e5, ...
                'OptimalityTolerance', 1e-7, 'StepTolerance', 1e-12);
            if K == 2
                s = 2 * (yi == 2) - 1;
                t = fminunc(@(t) mlTools.objBin(t, X, s, C, w), zeros(p + 1, 1), opts);
                W = t(1:p);  b = t(end);
            else
                Y = full(sparse(1:n, yi, 1, n, K));
                t = fminunc(@(t) mlTools.objMult(t, X, Y, C, w, p, K), zeros(p*K + K, 1), opts);
                W = reshape(t(1:p*K), p, K);  b = t(p*K+1:end)';
            end
        end

        function [f, gr] = objBin(t, X, s, C, w)
            p = size(X,2);  wv = t(1:p);  z = X * wv + t(end);
            m = -s .* z;
            l = max(m, 0) + log1p(exp(-abs(m)));                 % log(1 + exp(-s z))
            f = C * sum(w .* l) + 0.5 * (wv' * wv);
            r = -C * w .* s ./ (1 + exp(-m));                     % d/dz
            gr = [X' * r + wv; sum(r)];
        end

        function [f, gr] = objMult(t, X, Y, C, w, p, K)
            Wm = reshape(t(1:p*K), p, K);  b = t(p*K+1:end)';
            Z = X * Wm + b;  mx = max(Z, [], 2);
            lse = mx + log(sum(exp(Z - mx), 2));
            f = C * sum(w .* (lse - sum(Z .* Y, 2))) + 0.5 * sum(Wm(:).^2);
            S = exp(Z - lse);
            R = C * w .* (S - Y);
            gr = [reshape(X' * R + Wm, [], 1); sum(R, 1)'];
        end

        %% ---------------- evaluation ----------------
        function [Pr, classes, sel] = lopo(s, X, y, g, w)
            % Leave-one-participant-out class probabilities (folds run in parallel when a pool is open).
            if nargin < 5 || isempty(w), w = ones(size(X,1), 1); end
            classes = unique(y);  P = unique(g);  K = numel(classes);
            parts = cell(numel(P), 1);  sels = cell(numel(P), 1);
            parfor k = 1:numel(P)
                te = g == P(k);
                M = mlTools.fitPipe(s, X(~te,:), y(~te), w(~te)); %#ok<PFBNS>
                Pk = zeros(nnz(te), K);
                [~, j] = ismember(M.classes, classes);
                Pk(:, j) = mlTools.predictPipe(M, X(te,:));
                parts{k} = Pk;  sels{k} = M.sel;
            end
            Pr = zeros(numel(y), K);
            for k = 1:numel(P), Pr(g == P(k), :) = parts{k}; end
            sel = sels;
        end

        function pred = argmaxLab(Pr, classes)
            [~, j] = max(Pr, [], 2);  pred = classes(j);
            pred = pred(:);
        end

        function b = balAcc(y, pred)
            c = unique(y);  r = zeros(numel(c), 1);
            for k = 1:numel(c), m = strcmp(y, c{k}); r(k) = mean(strcmp(pred(m), c{k})); end
            b = mean(r);
        end

        function f = macroF1(y, pred)
            c = union(unique(y), unique(pred));  F = zeros(numel(c), 1);
            for k = 1:numel(c)
                tp = sum(strcmp(y, c{k}) & strcmp(pred, c{k}));
                pp = sum(strcmp(pred, c{k}));  ap = sum(strcmp(y, c{k}));
                if tp == 0, F(k) = 0; else, F(k) = 2 * tp / (pp + ap); end
            end
            f = mean(F);
        end

        function ci = bootCI(y, pred, g, other, nBoot, seed)
            % Participant bootstrap 95% CI of balanced accuracy [lo hi], plus [dlo dhi] of the
            % paired difference with `other` when given.
            if nargin < 4, other = []; end
            if nargin < 5 || isempty(nBoot), nBoot = 2000; end
            if nargin < 6, seed = 0; end
            rs = RandStream('mt19937ar', 'Seed', seed);
            P = unique(g);  idx = arrayfun(@(p) find(g == p), P, 'UniformOutput', false);
            a = nan(nBoot, 1);  d = nan(nBoot, 1);
            for b = 1:nBoot
                i = vertcat(idx{randi(rs, numel(P), numel(P), 1)});
                if numel(unique(y(i))) < 2, continue; end
                a(b) = mlTools.balAcc(y(i), pred(i));
                if ~isempty(other), d(b) = a(b) - mlTools.balAcc(y(i), other(i)); end
            end
            ci = prctile(a(~isnan(a)), [2.5 97.5]);
            if ~isempty(other), ci = [ci, prctile(d(~isnan(d)), [2.5 97.5])]; end
        end

        function yp = shuffleWithin(y, g, rs)
            yp = y;
            for p = unique(g)'
                i = find(g == p);
                yp(i) = y(i(randperm(rs, numel(i))));
            end
        end

        function [p, null95, null] = permTest(s, Xs, y, g, obs, n, seed)
            % Labels shuffled within participant; one model (numel(Xs) == 1) or the soft-vote fusion
            % of one model per matrix in Xs, all refitted on every permutation.
            null = zeros(n, 1);
            parfor r = 1:n
                rs = RandStream('mt19937ar', 'Seed', seed + r);
                yp = mlTools.shuffleWithin(y, g, rs);
                Pf = 0;  cl = {};
                for k = 1:numel(Xs)
                    [Pr, cl] = mlTools.lopo(s, Xs{k}, yp, g);
                    Pf = Pf + Pr / numel(Xs);
                end
                null(r) = mlTools.balAcc(yp, mlTools.argmaxLab(Pf, cl));
            end
            p = (1 + sum(null >= obs)) / (1 + n);
            null95 = prctile(null, 95);
        end

        %% ---------------- time-resolved features from the swing curves ----------------
        function [F, names] = cutFeatures(Cv, cut)
            % Lead-limb features from the curves cropped at `cut` % swing (value at the cut, and
            % max / min / mean / slope from toe-off to the cut). Cv.(sig) = n x 51 (0:2:100 %).
            k = round(cut / 2) + 1;
            sigs = {'thigh','shank','foot','footacc','zhc_h','zhc_x'};
            F = [];  names = {};
            for i = 1:numel(sigs)
                X = Cv.(sigs{i})(:, 1:k);
                F = [F, X(:, end)]; names{end+1} = [sigs{i} '_at']; %#ok<AGROW>
                if k >= 2
                    F = [F, max(X, [], 2, 'omitnan'), min(X, [], 2, 'omitnan'), mean(X, 2, 'omitnan'), ...
                         (X(:, end) - X(:, end-1)) / 0.02]; %#ok<AGROW>
                    names = [names, strcat(sigs{i}, {'_max','_min','_mean','_slope'})]; %#ok<AGROW>
                end
            end
        end

        function C = loadCurvesBoth(root, ids)
            % C.(lead|trail).(signal) = n x 51 swing curves (0:2:100 % swing), rows matched to ids.
            f = fullfile(root, 'Results', 'ML Dataset', 'Crossing_Curves_YoungAdults.csv');
            o = detectImportOptions(f);  o = setvartype(o, 'crossing_id', 'char');
            A = readtable(f, o);  [~, j] = ismember(ids, A.crossing_id);
            for limb = {'lead', 'trail'}
                for sg = {'thigh','shank','foot','footacc','zhc_h','zhc_x'}
                    cols = A.Properties.VariableNames(startsWith(A.Properties.VariableNames, [limb{1} '_' sg{1} '_p']));
                    M = nan(numel(ids), numel(cols));  M(j > 0, :) = A{j(j > 0), cols};
                    C.(limb{1}).(sg{1}) = M;
                end
            end
        end

        function [P, names] = shapeFeats(Cl)
            % Clearance-shape features of one limb from its ZHC height / progression curves and
            % foot tilt (0:2:100 % swing): peak height, progression to the peak, horizontal
            % distance and % of swing spent above 50/70/80/90 % of the peak, foot tilt at the
            % apex, progression after the apex, rise / fall steepness ratio. NaN if the curve is
            % incomplete or the peak is not above the stance level.
            H = Cl.zhc_h;  X = Cl.zhc_x;  A = Cl.foot;  n = size(H, 1);
            th = [0.5 0.7 0.8 0.9];  nt = numel(th);
            P = nan(n, 2 + 2 * nt + 3);
            for i = 1:n
                h = H(i,:);  x = X(i,:);
                if any(~isfinite(h)) || any(~isfinite(x)), continue; end
                [pk, ip] = max(h);
                if pk <= 0, continue; end
                P(i, 1) = pk;  P(i, 2) = x(ip) - x(1);
                for k = 1:nt
                    a = find(h >= th(k) * pk);
                    P(i, 2 + k) = x(a(end)) - x(a(1));
                    P(i, 2 + nt + k) = (a(end) - a(1)) * 2;
                end
                P(i, end-2) = A(i, ip);
                P(i, end-1) = x(end) - x(ip);
                P(i, end) = max(diff(h)) / max(-diff(h));
            end
            names = [{'h_peak', 'x_to_peak'}, arrayfun(@(t) sprintf('x_above_%02d', round(100*t)), th, 'UniformOutput', false), ...
                arrayfun(@(t) sprintf('t_above_%02d', round(100*t)), th, 'UniformOutput', false), {'foot_at_apex', 'x_after_peak', 'rise_fall'}];
        end

        function S = strideTable(root, T)
            % Every ZVP->ZVP stride of both feet in the sessions of the dataset's participants.
            % Columns: tn, side, cyc, t0 (stride start, Dot clock), cls (lead / trail / level /
            % other, from the dataset rows), cid (crossing_id), hcls (height class),
            % 12 full-stride features (strideFeat) and 6 online features available at the foot
            % apex (apexFeat, prefixed a_).
            rows = {};
            for tn = unique(T.participant_id)'
                d = load(fullfile(root, 'Results', 'Parameters Output', sprintf('Test %d', tn), sprintf('SegmentedParams_Test%d.mat', tn)), 'Seg');
                Sg = d.Seg;  Tp = T(T.participant_id == tn, :);
                for sd = 'LR'
                    z = Sg.(['zvp' sd]);  tz = Sg.zhc.(sd).tZvp;  PT = Sg.zhc.(sd).posTime;
                    n = min(numel(z) - 1, size(PT, 3));
                    cls = repmat("other", n, 1);  cid = repmat("", n, 1);  hc = repmat("", n, 1);
                    for r = 1:height(Tp)
                        ll = Tp.leading_limb{r};  if isempty(ll), continue; end
                        tl = 'R';  if ll == 'R', tl = 'L'; end
                        lab = ["lead" "trail"];  if Tp.is_level(r) == 1, lab = ["level" "level"]; end
                        for k = 1:2
                            if k == 1, side = ll; tt = Tp.lead_toeoff_t(r); else, side = tl; tt = Tp.trail_toeoff_t(r); end
                            if side ~= sd || ~isfinite(tt), continue; end
                            c = find(tz(1:end-1) <= tt & tt < tz(2:end), 1);
                            if ~isempty(c) && c <= n, cls(c) = lab(k); cid(c) = string(Tp.crossing_id{r}); hc(c) = string(Tp.height_class{r}); end
                        end
                    end
                    for c = 1:n
                        Lc = z(c+1) - z(c) + 1;  P = PT(1:min(Lc, size(PT,1)), :, c);
                        rows(end+1, :) = [{tn, sd, c, tz(c), cls(c), cid(c), hc(c)}, ...
                            num2cell(mlTools.strideFeat(P, tz(c+1) - tz(c))), num2cell(mlTools.apexFeat(P))]; %#ok<AGROW>
                    end
                end
            end
            S = cell2table(rows, 'VariableNames', [{'tn','side','cyc','t0','cls','cid','hcls'}, mlTools.strideFeatNames(), ...
                {'a_h_peak','a_t_peak','a_dist_peak','a_vz_max','a_vz_mean','a_h_pre'}]);
            S.cls = string(S.cls);  S.side = string(S.side);  S.cid = string(S.cid);  S.hcls = string(S.hcls);
        end

        function n = strideFeatNames()
            n = {'h_peak','t_peak','t_above50','t_above70','t_above90','x_above50','x_above70','x_above90','stride_len','vz_max','h_end','dur'};
        end

        function f = strideFeat(P, dur)
            % 12 features of one ZVP->ZVP stride from its ZHC position (m): height relative to the
            % start, progression along the net horizontal displacement.
            f = nan(1, 12);
            if size(P, 1) < 10 || any(~isfinite(P(:))), return; end
            u = P(end,1:2) - P(1,1:2);  sl = norm(u);  if sl > 0, u = u / sl; end
            h = (P(:,3) - P(1,3)) * 1000;  x = (P(:,1:2) - P(1,1:2)) * u' * 1000;
            n = numel(h);  [pk, ip] = max(h);
            f(1) = pk;  f(2) = (ip - 1) / (n - 1);
            th = [0.5 0.7 0.9];
            for k = 1:3
                if pk <= 0, break; end
                a = find(h >= th(k) * pk);
                f(2 + k) = (a(end) - a(1)) / (n - 1);  f(5 + k) = x(a(end)) - x(a(1));
            end
            f(9) = sl * 1000;  f(10) = max(diff(h)) * 60;  f(11) = h(end);  f(12) = dur;
        end

        function f = apexFeat(P)
            % Online features known when the foot reaches its highest point (no data after the
            % apex): peak height (mm), time from the stride start (s), horizontal distance
            % travelled (mm), max and mean vertical speed before the apex (mm/s), height 0.1 s
            % before the apex (mm). 60 Hz ZHC samples.
            f = nan(1, 6);
            if size(P, 1) < 10 || any(~isfinite(P(:))), return; end
            h = (P(:,3) - P(1,3)) * 1000;  [pk, ip] = max(h);
            if ip < 4, return; end
            vz = diff(h(1:ip)) * 60;
            f = [pk, (ip - 1) / 60, norm(P(ip,1:2) - P(1,1:2)) * 1000, max(vz), mean(vz), h(max(1, ip - 6))];
        end

        function [A, k] = loadAligned(root, ids)
            % A.(lead|trail).(signal) = n x nK Dot signals at samples k (60 Hz) around the trailing toe
            % lift-off seen by the camera (Crossing_Aligned_YoungAdults.csv), rows matched to ids.
            f = fullfile(root, 'Results', 'ML Dataset', 'Crossing_Aligned_YoungAdults.csv');
            o = detectImportOptions(f);  o = setvartype(o, 'crossing_id', 'char');
            B = readtable(f, o);  [~, j] = ismember(ids, B.crossing_id);  v = B.Properties.VariableNames;
            for limb = {'lead', 'trail'}
                for sg = {'thigh','shank','foot','footacc','zhc_h'}
                    cols = v(startsWith(v, [limb{1} '_' sg{1} '_s']));
                    M = nan(numel(ids), numel(cols));  M(j > 0, :) = B{j(j > 0), cols};
                    A.(limb{1}).(sg{1}) = M;
                end
            end
            c = v(startsWith(v, 'lead_thigh_s'));
            k = cellfun(@(s) (1 - 2 * (s(end-3) == 'm')) * str2double(s(end-2:end)), c);
        end

        function Cv = loadCurves(root, ids)
            f = fullfile(root, 'Results', 'ML Dataset', 'Crossing_Curves_YoungAdults.csv');
            o = detectImportOptions(f);  o = setvartype(o, 'crossing_id', 'char');
            C = readtable(f, o);
            [~, j] = ismember(ids, C.crossing_id);
            sigs = {'thigh','shank','foot','footacc','zhc_h','zhc_x'};
            for i = 1:numel(sigs)
                cols = C.Properties.VariableNames(startsWith(C.Properties.VariableNames, ['lead_' sigs{i} '_p']));
                A = C{:, cols};
                M = nan(numel(ids), numel(cols));  M(j > 0, :) = A(j(j > 0), :);
                Cv.(sigs{i}) = M;
            end
        end

        %% ---------------- figures ----------------
        function figures(out, name, S)
            % Saves the numbers behind figure group NAME (fields of S) to <out>/figdata/NAME.mat and
            % draws them with crossing_ml_figures (step 9 plot template). A plotting error is reported
            % but never stops an analysis; crossing_ml_figures redraws from the saved file.
            d = fullfile(out, 'figdata');
            if ~isfolder(d), mkdir(d); end
            save(fullfile(d, [name '.mat']), '-struct', 'S');
            try
                crossing_ml_figures(name);
            catch err
                warning('mlTools:figures', 'figure group %s not drawn: %s', name, err.message);
            end
        end
    end
end
