clc; clear; close all;
addpath(fileparts(mfilename('fullpath')));
%% ========================================================================
%% STEP 10 - GROUP STATISTICS (across participants)
%% ========================================================================
% Reads the step9 aggregate (G.perParticipant: one value per participant x condition
% for every parameter) and runs the group-level statistics for the obstacle-crossing
% study. Within-subject design: Width(W1,W2) x Height(H1,H2,H3) x Role(Leading,
% Trailing), with Level_Walk as the baseline.
%
% For EVERY parameter (clearance, spatiotemporal, ROM, joint max/min, segment ROM,
% peak angles, peak timing) it reports:
%   - descriptives (mean +/- SD per condition)
%   - NON-PARAMETRIC (primary, robust at n=9): Friedman (Height), Wilcoxon signed-rank
%     (Width, Role, and crossing-vs-Level_Walk), with effect sizes
%   - PARAMETRIC alongside: Width x Height x Role repeated-measures ANOVA
%     (Greenhouse-Geisser p, partial eta^2)
%   - normality (Lilliefors) to justify the non-parametric emphasis
%   - Benjamini-Hochberg FDR correction across parameters (per effect)
%
% Outputs (Results/Group Analysis/Statistics/):
%   - GroupStats_<cohort>_SPSS.xlsx   : Wide (SPSS-ready) + Long + results sheets
%   - GroupStats_<cohort>_Report.md   : significance tables + plain-language summary
%   - Figures/                        : distributions, significance bars, p-heatmap, Q-Q
%   - a summary table printed to the command window

%% ===================== CONFIG =====================
COHORT = 'YoungAdults';
ALPHA  = 0.05;
root   = fileparts(fileparts(mfilename('fullpath')));
gFile  = fullfile(root,'Results','Group Analysis',sprintf('GroupCrossing_%s.mat',COHORT));
outDir = fullfile(root,'Results','Group Analysis','Statistics');
figDir = fullfile(outDir,'Figures');
if ~isfolder(figDir), mkdir(figDir); end
if ~isfile(gFile), error('Run step9 first - %s not found.', gFile); end
S = load(gFile);  G = S.G;  pp = G.perParticipant;
tests = pp.tests(:);  nSubj = numel(tests);
fprintf('STEP 10 - group statistics | cohort %s | n = %d participants\n', COHORT, nSubj);

%% ===================== PARAMETER CATALOG =====================
% {group, key, display, unit}; matrix = pp.(group).(key) is [nSubj x nCond].
CAT = {
  'T1','clr_toe','Toe clearance','cm';       'T1','clr_heel','Heel clearance','cm';
  'T1','clr_min','Min clearance','cm';       'T1','lift_dist','Take-off distance','cm';
  'T1','land_dist','Landing distance','cm';
  'SPT','stride','Stride length','cm';        'SPT','cadence','Cadence','steps/min';
  'SPT','speed','Speed','m/s';
  'ROM','hip_flexion','Hip ROM','deg';        'ROM','knee_angle','Knee ROM','deg';
  'ROM','ankle_angle','Ankle ROM','deg';
  'JMAX','hip_flexion','Hip angle max','deg';  'JMAX','knee_angle','Knee angle max','deg';
  'JMAX','ankle_angle','Ankle angle max','deg';
  'JMIN','hip_flexion','Hip angle min','deg';  'JMIN','knee_angle','Knee angle min','deg';
  'JMIN','ankle_angle','Ankle angle min','deg';
  'SROM','Thigh','Thigh tilt ROM','deg';      'SROM','Shank','Shank tilt ROM','deg';
  'SROM','Foot','Foot tilt ROM','deg';
  'PEX','hip_pk_flex','Hip peak flexion','deg';     'PEX','hip_pk_ext','Hip peak extension','deg';
  'PEX','knee_pk_flex','Knee peak flexion','deg';   'PEX','ank_plant','Ankle plantarflexion','deg';
  'PEX','ank_dorsi','Ankle dorsiflexion','deg';     'PEX','thigh_fwd','Thigh fwd tilt','deg';
  'PEX','thigh_back','Thigh back tilt','deg';       'PEX','shank_back','Shank back tilt','deg';
  'PEX','shank_fwd','Shank fwd tilt','deg';         'PEX','foot_toedown','Foot toe-down','deg';
  'PEX','foot_toeup','Foot toe-up','deg';
  'PKT','hip_flexion','Hip peak timing','%GC';  'PKT','knee_angle','Knee peak timing','%GC';
  'PKT','ankle_angle','Ankle peak timing','%GC';'PKT','Thigh','Thigh peak timing','%GC';
  'PKT','shank','Shank peak timing','%GC';      'PKT','Foot','Foot peak timing','%GC';
};
% PKT uses capitalised segment keys; fix 'shank' -> 'Shank'
CAT(strcmp(CAT(:,2),'shank') & strcmp(CAT(:,1),'PKT'), 2) = {'Shank'};

%% ===================== CONDITION / FACTOR DESIGN =====================
condName = G.condName(:)';            % 12 crossing conditions (W x H x Role)
nC = numel(condName);
[Wd, Ht, Rl] = deal(cell(1,nC));
for c = 1:nC
    t = split(condName{c}, '_');      % e.g. {'W1','H1','Leading'}
    Wd{c} = t{1};  Ht{c} = t{2};  Rl{c} = t{3};
end
Wc = categorical(Wd);  Hc = categorical(Ht);  Rc = categorical(Rl);
wd = table(Wc', Hc', Rc', 'VariableNames', {'Width','Height','Role'});

%% ===================== PER-PARAMETER STATISTICS =====================
NP = size(CAT,1);
R = struct('group',{},'key',{},'disp',{},'unit',{},'nUsed',{}, ...
           'desc',{},'pNormFail',{}, ...
           'pW',{},'pH',{},'pR',{},'pWH',{},'pWR',{},'pHR',{},'pWHR',{},'eta',{}, ...
           'npH_p',{},'npH_W',{},'npW_p',{},'npW_r',{},'npR_p',{},'npR_r',{}, ...
           'vsLevel_p',{},'vsLevel_dir',{},'hasLevel',{});
Yall = cell(1,NP);   % crossing data [nSubj x 12] per parameter (for SPSS/figures)
Ylev = cell(1,NP);   % level-walk data [nSubj x 1] per parameter
for i = 1:NP
    grp = CAT{i,1};  key = CAT{i,2};
    M = pp.(grp).(key);                        % [nSubj x nCondAll]
    Ycr = M(:, 1:nC);                          % crossing conditions (first 12)
    hasLevel = size(M,2) > nC;
    YL = nan(nSubj,1);  if hasLevel, YL = M(:, nC+1); end
    Yall{i} = Ycr;  Ylev{i} = YL;

    r = struct();
    r.group = grp;  r.key = key;  r.disp = CAT{i,3};  r.unit = CAT{i,4};  r.hasLevel = hasLevel;
    % descriptives per condition
    r.desc = [mean(Ycr,1,'omitnan'); std(Ycr,0,1,'omitnan'); sum(~isnan(Ycr),1)];
    % normality (Lilliefors) on pooled within-subject-centred data
    r.pNormFail = normFail(Ycr);
    % ---- parametric RM-ANOVA (Width x Height x Role) ----
    [r.pW,r.pH,r.pR,r.pWH,r.pWR,r.pHR,r.pWHR,r.eta,r.nUsed] = rmAnova(Ycr, wd);
    % ---- non-parametric ----
    [r.npH_p, r.npH_W] = friedmanFactor(Ycr, Ht, {'H1','H2','H3'});     % Height (Friedman)
    [r.npW_p, r.npW_r] = wilcoxFactor(Ycr, Wd, 'W1','W2');              % Width (Wilcoxon)
    [r.npR_p, r.npR_r] = wilcoxFactor(Ycr, Rl, 'Leading','Trailing');  % Role (Wilcoxon)
    % ---- crossing vs level walk ----
    [r.vsLevel_p, r.vsLevel_dir] = deal(NaN,'');
    if hasLevel
        cr = mean(Ycr,2,'omitnan');  g = ~isnan(cr) & ~isnan(YL);
        if nnz(g) >= 4
            r.vsLevel_p = signrank(cr(g), YL(g));
            r.vsLevel_dir = tern(median(cr(g)-YL(g))>=0,'higher','lower');
        end
    end
    R(i) = r;
end

% ---- FDR (Benjamini-Hochberg) across parameters, per effect ----
fdr = struct();
fdr.H = bh([R.npH_p]);  fdr.W = bh([R.npW_p]);  fdr.R = bh([R.npR_p]);  fdr.vsL = bh([R.vsLevel_p]);
fdr.aH = bh([R.pH]);    fdr.aW = bh([R.pW]);    fdr.aR = bh([R.pR]);

%% ===================== OUTPUTS =====================
xlsFile = fullfile(outDir, sprintf('GroupStats_%s_SPSS.xlsx', COHORT));
if isfile(xlsFile), delete(xlsFile); end
writeWideLong(xlsFile, CAT, Yall, Ylev, tests, condName, Wd, Ht, Rl);
writeResultsSheets(xlsFile, R, fdr, ALPHA);
fprintf('Saved SPSS workbook -> %s\n', xlsFile);

mdFile = fullfile(outDir, sprintf('GroupStats_%s_Report.md', COHORT));
writeReport(mdFile, R, fdr, ALPHA, COHORT, nSubj, tests);
fprintf('Saved report -> %s\n', mdFile);

printSummary(R, fdr, ALPHA);                                   % command-window tables
makeFigures(figDir, R, Yall, Ylev, condName, Ht, Rl, ALPHA);   % distributions, heatmap, Q-Q
fprintf('Saved figures -> %s\n', figDir);
fprintf('\nDone. Statistics for %d parameters, n = %d.\n', NP, nSubj);

%% ============================ functions ============================
function tf = normFail(Y)
% Lilliefors on each column's within-subject deviations; returns fraction failing.
    f = 0; n = 0;
    for c = 1:size(Y,2)
        x = Y(~isnan(Y(:,c)),c);  if numel(x) < 5, continue; end
        n = n + 1;
        try
            h = lillietest(x, 'Alpha', 0.05);
        catch
            h = 0;
        end
        f = f + (h==1);
    end
    if n == 0, tf = NaN; else, tf = f/n; end
end

function [pW,pH,pR,pWH,pWR,pHR,pWHR,eta,nUsed] = rmAnova(Y, wd)
% Width x Height x Role repeated-measures ANOVA (complete cases). Returns GG p-values
% and a partial eta^2 for the Height main effect (the primary factor). NaN if n<4.
    [pW,pH,pR,pWH,pWR,pHR,pWHR] = deal(NaN);  eta = NaN;
    good = all(~isnan(Y),2);  nUsed = nnz(good);
    if nUsed < 4, return; end
    Yg = Y(good,:);
    vn = arrayfun(@(k) sprintf('y%d',k), 1:size(Yg,2), 'uni',0);
    T = array2table(Yg, 'VariableNames', vn);
    try
        rm = fitrm(T, sprintf('%s-%s ~ 1', vn{1}, vn{end}), 'WithinDesign', wd);
        a = ranova(rm, 'WithinModel', 'Width*Height*Role');
        rn = string(a.Properties.RowNames);
        pW  = getp(a,rn,'Width');        pH  = getp(a,rn,'Height');       pR = getp(a,rn,'Role');
        pWH = getp(a,rn,'Width:Height'); pWR = getp(a,rn,'Width:Role');
        pHR = getp(a,rn,'Height:Role');  pWHR= getp(a,rn,'Width:Height:Role');
        eta = etaSq(a, rn, 'Height');
    catch ME
        warning('RM-ANOVA failed (%s): %s', vn{1}, ME.message);
    end
end

function p = getp(a, rn, eff)
    i = find(rn == "(Intercept):"+eff, 1);  p = NaN;
    if isempty(i), return; end
    if any(strcmp(a.Properties.VariableNames,'pValueGG')) && ~isnan(a.pValueGG(i)), p = a.pValueGG(i);
    else, p = a.pValue(i); end
end

function e = etaSq(a, rn, eff)
    i = find(rn == "(Intercept):"+eff, 1);  j = find(rn == "Error("+eff+")", 1);  e = NaN;
    if isempty(i) || isempty(j), return; end
    e = a.SumSq(i) / (a.SumSq(i) + a.SumSq(j));
end

function [p, W] = friedmanFactor(Y, lvlOf, lvls)
% Friedman across the factor levels (each participant's mean over the other factors).
    p = NaN; W = NaN;
    X = nan(size(Y,1), numel(lvls));
    for L = 1:numel(lvls), X(:,L) = mean(Y(:, strcmp(lvlOf, lvls{L})), 2, 'omitnan'); end
    good = all(~isnan(X),2);  X = X(good,:);
    if size(X,1) < 4, return; end
    try
        p = friedman(X, 1, 'off');
        chi2 = friedmanChi(X);  W = chi2 / (size(X,1)*(size(X,2)-1));   % Kendall's W
    catch
    end
end

function chi2 = friedmanChi(X)
    [n,k] = size(X);  Rk = zeros(n,k);
    for i = 1:n, [~,o] = sort(X(i,:)); Rk(i,o) = 1:k; end
    Rj = sum(Rk,1);
    chi2 = 12/(n*k*(k+1))*sum(Rj.^2) - 3*n*(k+1);
end

function [p, r] = wilcoxFactor(Y, lvlOf, a, b)
% Wilcoxon signed-rank between two factor levels (participant means over others).
    p = NaN; r = NaN;
    xa = mean(Y(:, strcmp(lvlOf,a)), 2, 'omitnan');
    xb = mean(Y(:, strcmp(lvlOf,b)), 2, 'omitnan');
    g = ~isnan(xa) & ~isnan(xb);
    if nnz(g) < 4, return; end
    try
        [p,~,st] = signrank(xa(g), xb(g));
        if isfield(st,'zval') && ~isnan(st.zval), r = abs(st.zval)/sqrt(nnz(g)); end   % effect size r
    catch
    end
end

function q = bh(p)
% Benjamini-Hochberg FDR-adjusted p-values (NaN-safe).
    q = nan(size(p));  idx = find(~isnan(p));  pp = p(idx);
    [s,o] = sort(pp);  m = numel(s);  adj = s .* m ./ (1:m);
    for i = m-1:-1:1, adj(i) = min(adj(i), adj(i+1)); end
    adj = min(adj,1);  out = nan(1,m);  out(o) = adj;  q(idx) = out;
end

function s = tern(c,a,b), if c, s=a; else, s=b; end, end

function pid = pidOf(grp,key), pid = matlab.lang.makeValidName(sprintf('%s_%s',grp,key)); end

function writeWideLong(xlsFile, CAT, Yall, Ylev, tests, condName, Wd, Ht, Rl)
% WIDE (SPSS-ready: one row per participant) + LONG (one row per participant x cond).
    NP = size(CAT,1);  nC = numel(condName);  nS = numel(tests);
    Wt = table(tests, 'VariableNames', {'Test'});
    for i = 1:NP
        pid = pidOf(CAT{i,1},CAT{i,2});  Y = Yall{i};
        for c = 1:nC
            Wt.(matlab.lang.makeValidName(sprintf('%s_%s', pid, condName{c}))) = Y(:,c);
        end
        if any(~isnan(Ylev{i})), Wt.(matlab.lang.makeValidName([pid '_Level'])) = Ylev{i}; end
    end
    writetable(Wt, xlsFile, 'Sheet', 'Wide');
    % LONG
    testCol = []; wCol = {}; hCol = {}; rCol = {};
    for c = 1:nC
        testCol = [testCol; tests]; %#ok<AGROW>
        wCol = [wCol; repmat(Wd(c),nS,1)];  hCol = [hCol; repmat(Ht(c),nS,1)];  rCol = [rCol; repmat(Rl(c),nS,1)]; %#ok<AGROW>
    end
    L = table(testCol, wCol, hCol, rCol, 'VariableNames', {'Test','Width','Height','Role'});
    for i = 1:NP
        col = [];  Y = Yall{i};  for c = 1:nC, col = [col; Y(:,c)]; end %#ok<AGROW>
        L.(pidOf(CAT{i,1},CAT{i,2})) = col;
    end
    Lv = table(tests, repmat({'Level'},nS,1), repmat({'Level'},nS,1), repmat({'Level'},nS,1), ...
        'VariableNames', {'Test','Width','Height','Role'});
    for i = 1:NP, Lv.(pidOf(CAT{i,1},CAT{i,2})) = Ylev{i}; end
    writetable([L; Lv], xlsFile, 'Sheet', 'Long');
    % DESCRIPTIVES (long: param, condition, mean, sd, n)
    P = {}; Cc = {}; Mn = []; Sd = []; Nn = [];
    for i = 1:NP
        Y = Yall{i};  nm = sprintf('%s (%s)', CAT{i,3}, CAT{i,4});
        for c = 1:nC
            x = Y(~isnan(Y(:,c)),c);
            P{end+1,1}=nm; Cc{end+1,1}=condName{c}; Mn(end+1,1)=mean(x); Sd(end+1,1)=std(x); Nn(end+1,1)=numel(x); %#ok<AGROW>
        end
        if any(~isnan(Ylev{i}))
            x = Ylev{i}(~isnan(Ylev{i}));
            P{end+1,1}=nm; Cc{end+1,1}='Level_Walk'; Mn(end+1,1)=mean(x); Sd(end+1,1)=std(x); Nn(end+1,1)=numel(x); %#ok<AGROW>
        end
    end
    writetable(table(P,Cc,round(Mn,2),round(Sd,2),Nn,'VariableNames',{'Parameter','Condition','Mean','SD','n'}), ...
        xlsFile, 'Sheet', 'Descriptives');
end

function writeResultsSheets(xlsFile, R, fdr, ~)
    nm = arrayfun(@(r) string(sprintf('%s (%s)', r.disp, r.unit)), R)';
    A = table(nm, [R.nUsed]', rnd([R.pW]'), rnd([R.pH]'), rnd([R.pR]'), rnd([R.pWH]'), rnd([R.pWR]'), ...
              rnd([R.pHR]'), rnd([R.pWHR]'), rnd([R.eta]'), rnd(fdr.aH'), rnd(fdr.aW'), rnd(fdr.aR'), ...
        'VariableNames', {'Parameter','n','p_Width','p_Height','p_Role','p_WxH','p_WxR','p_HxR','p_WxHxR','eta2_Height','FDR_Height','FDR_Width','FDR_Role'});
    writetable(A, xlsFile, 'Sheet', 'RM_ANOVA');
    N = table(nm, rnd([R.npH_p]'), rnd(fdr.H'), rnd([R.npH_W]'), rnd([R.npW_p]'), rnd(fdr.W'), rnd([R.npW_r]'), ...
              rnd([R.npR_p]'), rnd(fdr.R'), rnd([R.npR_r]'), ...
        'VariableNames', {'Parameter','Height_p','Height_FDR','Height_W','Width_p','Width_FDR','Width_r','Role_p','Role_FDR','Role_r'});
    writetable(N, xlsFile, 'Sheet', 'NonParam');
    V = table(nm, rnd([R.vsLevel_p]'), rnd(fdr.vsL'), string({R.vsLevel_dir})', ...
        'VariableNames', {'Parameter','p','FDR','Crossing_vs_Level'});
    writetable(V, xlsFile, 'Sheet', 'vs_LevelWalk');
end

function y = rnd(x), y = round(x,4); end

function s = fmtp(p, q)
% "p [FDR]" with a * if FDR-significant, ** if < .01.
    if isnan(p), s = '-'; return; end
    star = '';  if q < 0.01, star = ' **'; elseif q < 0.05, star = ' *'; end
    s = sprintf('%.3f [%.3f]%s', p, q, star);
end

function writeReport(mdFile, R, fdr, ALPHA, COHORT, nSubj, tests)
    fid = fopen(mdFile,'w');  if fid < 0, warning('cannot write %s', mdFile); return; end
    fprintf(fid, '# Group statistics — %s (n = %d)\n\n', COHORT, nSubj);
    fprintf(fid, 'Participants: `%s`\n\n', mat2str(tests'));
    fprintf(fid, '**Design:** within-subject **Width**(W1=5cm, W2=15cm) × **Height**(H1,H2,H3) × **Role**(Leading,Trailing); `Level_Walk` = baseline.\n\n');
    fprintf(fid, '**Tests:** primary = non-parametric (Friedman for Height; Wilcoxon signed-rank for Width, Role, and crossing vs Level). Parametric **Width×Height×Role RM-ANOVA** (Greenhouse–Geisser) reported alongside. p-values **FDR-corrected** (Benjamini–Hochberg) across parameters, per effect; α = %.2f. `*` FDR<.05, `**` FDR<.01.\n\n', ALPHA);
    % ---- significant summaries ----
    fprintf(fid, '## Significant effects (non-parametric, FDR-corrected)\n\n');
    sigList(fid, 'Obstacle HEIGHT', R, fdr.H, ALPHA);
    sigList(fid, 'Obstacle WIDTH',  R, fdr.W, ALPHA);
    sigList(fid, 'Limb ROLE (Leading vs Trailing)', R, fdr.R, ALPHA);
    sigList(fid, 'Crossing vs Level walk', R, fdr.vsL, ALPHA);
    % ---- full non-parametric table ----
    fprintf(fid, '\n## Non-parametric results — p [FDR]\n\n');
    fprintf(fid, '| Parameter | Height (Friedman) | Width (Wilcoxon) | Role (Wilcoxon) | Crossing vs Level |\n|---|---|---|---|---|\n');
    for i = 1:numel(R)
        fprintf(fid, '| %s (%s) | %s | %s | %s | %s |\n', R(i).disp, R(i).unit, ...
            fmtp(R(i).npH_p,fdr.H(i)), fmtp(R(i).npW_p,fdr.W(i)), fmtp(R(i).npR_p,fdr.R(i)), fmtp(R(i).vsLevel_p,fdr.vsL(i)));
    end
    % ---- parametric RM-ANOVA table ----
    fprintf(fid, '\n## Parametric RM-ANOVA — p (Greenhouse–Geisser)\n\n');
    fprintf(fid, '| Parameter | n | Width | Height | Role | W×H | W×R | H×R | W×H×R | η²(Height) |\n|---|--|--|--|--|--|--|--|--|--|\n');
    for i = 1:numel(R)
        fprintf(fid, '| %s | %d | %s | %s | %s | %s | %s | %s | %s | %s |\n', R(i).disp, R(i).nUsed, ...
            pp3(R(i).pW), pp3(R(i).pH), pp3(R(i).pR), pp3(R(i).pWH), pp3(R(i).pWR), pp3(R(i).pHR), pp3(R(i).pWHR), pp3(R(i).eta));
    end
    % ---- descriptives (mean +/- SD per condition) ----
    fprintf(fid, '\n## Descriptives (mean ± SD per condition)\n\n');
    fprintf(fid, '> Full per-condition values are in the SPSS workbook (Descriptives sheet) and the step9 results file.\n\n');
    fprintf(fid, '\n---\n*Non-parametric is the headline (n=%d); treat RM-ANOVA as supportive. Normality (Lilliefors) flagged where >30%% of conditions were non-normal.*\n', nSubj);
    fclose(fid);
end

function sigList(fid, ttl, R, q, ALPHA)
    fprintf(fid, '**%s:** ', ttl);
    k = find(q < ALPHA & ~isnan(q));
    if isempty(k), fprintf(fid, 'none.\n\n'); return; end
    [~,o] = sort(q(k));  k = k(o);
    items = arrayfun(@(i) sprintf('%s (%s) [FDR=%.3f]', R(i).disp, R(i).unit, q(i)), k, 'uni',0);
    fprintf(fid, '%s.\n\n', strjoin(items, '; '));
end

function s = pp3(x)
    if isnan(x), s = '-'; return; end
    if x < 0.001, s = '<.001'; else, s = sprintf('%.3f', x); end
end

function printSummary(R, fdr, ALPHA)
    fprintf('\n================= SIGNIFICANT EFFECTS (non-parametric, FDR) =================\n');
    eff = {'Obstacle Height', [R.npH_p], fdr.H;  'Obstacle Width', [R.npW_p], fdr.W; ...
           'Limb Role', [R.npR_p], fdr.R;        'Crossing vs Level', [R.vsLevel_p], fdr.vsL};
    for e = 1:size(eff,1)
        q = eff{e,3};  k = find(q < ALPHA & ~isnan(q));
        fprintf('\n[%s]  %d significant\n', eff{e,1}, numel(k));
        [~,o] = sort(q(k));
        for i = k(o)
            fprintf('   %-26s p=%.3f  FDR=%.3f\n', sprintf('%s (%s)',R(i).disp,R(i).unit), eff{e,2}(i), q(i));
        end
    end
    fprintf('\n============================================================================\n');
end

function makeFigures(figDir, R, Yall, Ylev, ~, Ht, Rl, ALPHA)
    FN = 'Arial';
    % ---- p-value heatmap (parameter x effect) ----
    NP = numel(R);
    Pm = [[R.npH_p]', [R.npW_p]', [R.npR_p]', [R.vsLevel_p]'];
    f1 = figure('Color','w','Position',[60 60 760 1000]);
    imagesc(-log10(Pm), 'AlphaData', ~isnan(Pm));  colormap(flipud(hot));  cb = colorbar;
    cb.Label.String = '-log_{10}(p)';
    set(gca,'XTick',1:4,'XTickLabel',{'Height','Width','Role','vs Level'}, ...
        'YTick',1:NP,'YTickLabel',arrayfun(@(r) sprintf('%s (%s)',r.disp,r.unit),R,'uni',0), ...
        'FontName',FN,'FontSize',9,'TickLabelInterpreter','none');
    hold on;  clim([0 max(3,max(-log10(Pm(:)),[],'omitnan'))]);
    for i=1:NP, for j=1:4, if ~isnan(Pm(i,j)) && Pm(i,j)<ALPHA, text(j,i,'*','HorizontalAlignment','center','Color','c','FontWeight','bold'); end, end, end
    title(sprintf('Significance heatmap  (* p<%.2f uncorrected)', ALPHA),'FontName',FN);
    exportgraphics(f1, fullfile(figDir,'pvalue_heatmap.png'), 'Resolution',150);  close(f1);
    % ---- distribution boxplots by HEIGHT, grouped by Role, for each parameter ----
    grps = unique({R.group},'stable');
    for gi = 1:numel(grps)
        idx = find(strcmp({R.group}, grps{gi}));
        nP = numel(idx);  nc = min(3,nP);  nr = ceil(nP/nc);
        f = figure('Color','w','Position',[40 40 520*nc 360*nr]);
        for a = 1:nP
            ri = idx(a);  Y = Yall{ri};  subplot(nr,nc,a); hold on; box on;
            % group by Height x Role
            labs = {}; data = {};
            for H = {'H1','H2','H3'}
                for Rr = {'Leading','Trailing'}
                    sel = strcmp(Ht,H{1}) & strcmp(Rl,Rr{1});
                    v = Y(:,sel);  v = v(~isnan(v));
                    labs{end+1} = sprintf('%s %s',H{1},Rr{1}(1)); data{end+1} = v(:); %#ok<AGROW>
                end
            end
            boxplotCells(gca, data, labs);
            if any(~isnan(Ylev{ri})), yline(median(Ylev{ri},'omitnan'),'--r','level'); end
            title(sprintf('%s (%s)',R(ri).disp,R(ri).unit),'FontName',FN,'Interpreter','none','FontSize',11);
            set(gca,'FontName',FN,'FontSize',9);
        end
        exportgraphics(f, fullfile(figDir, sprintf('dist_%s.png', grps{gi})), 'Resolution',150);  close(f);
    end
end

function boxplotCells(ax, data, labs)
    n = numel(data);
    for i = 1:n
        x = data{i};  if isempty(x), continue; end
        q = quantile(x,[.25 .5 .75]);  w = 0.3;
        fill(ax,[i-w i+w i+w i-w],[q(1) q(1) q(3) q(3)],[.8 .88 .98],'EdgeColor',[.2 .4 .7]);
        plot(ax,[i-w i+w],[q(2) q(2)],'Color',[.2 .4 .7],'LineWidth',2);
        plot(ax,i+(rand(numel(x),1)-.5)*.2, x, 'o','Color',[.3 .3 .3],'MarkerSize',3,'MarkerFaceColor',[.5 .5 .5]);
    end
    set(ax,'XTick',1:n,'XTickLabel',labs);  xtickangle(ax,35);  xlim(ax,[.5 n+.5]);
end

