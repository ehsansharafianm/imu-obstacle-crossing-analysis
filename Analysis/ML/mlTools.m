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
            % spec('logreg', 'C', 0.1, 'k', 0) | spec('forest', 'nTrees', 500)
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
    end
end
