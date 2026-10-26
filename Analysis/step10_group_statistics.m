clc; clear; close all;
addpath(fileparts(mfilename('fullpath')));
%% ========================================================================
%% STEP 10 - GROUP STATISTICS (across participants)
%% ========================================================================
% Reads the step9 aggregate (G.perParticipant: one value per participant x condition
% for every parameter) and runs the group statistics for the obstacle-crossing study.
%
% LEADING and TRAILING limbs are treated as SEPARATE CLASSES: every test is run
% INDEPENDENTLY within Leading and within Trailing (no Role factor, no Leading-vs-
% Trailing comparison). Within each class the design is Width(W1,W2) x Height(H1,H2,H3)
% over the 6 obstacles, with Level_Walk as the baseline.
%
% Per parameter, per class, it reports:
%   - descriptives (mean +/- SD per condition)
%   - NON-PARAMETRIC (primary, n=9): Friedman (obstacle Height; and omnibus across the
%     6 obstacles) + Wilcoxon signed-rank (Width, and crossing-vs-Level_Walk), effect sizes
%   - PARAMETRIC alongside: Width x Height repeated-measures ANOVA (Greenhouse-Geisser,
%     partial eta^2)
%   - normality (Lilliefors); Benjamini-Hochberg FDR across parameters, per effect, per class
%
% Outputs (Results/Group Analysis/Statistics/):
%   - GroupStats_<cohort>_SPSS.xlsx : Wide (SPSS) + Long + Descriptives +
%                                     Results_Leading + Results_Trailing
%   - GroupStats_<cohort>_Report.md : Leading & Trailing significance sections
%   - Figures/                      : per-class p-value heatmap + distribution figures
%   - command-window summary

%% ===================== CONFIG =====================
COHORT = 'YoungAdults';
ALPHA  = 0.05;
FIG_SKIP = {'clr_toe','clr_heel'};   % leave OUT of the distribution figures (min clearance is enough)
root   = fileparts(fileparts(mfilename('fullpath')));
gFile  = fullfile(root,'Results','Group Analysis',sprintf('GroupCrossing_%s.mat',COHORT));
outDir = fullfile(root,'Results','Group Analysis','Statistics');
figDir = fullfile(outDir,'Figures');
if ~isfolder(figDir), mkdir(figDir); end
if ~isfile(gFile), error('Run step9 first - %s not found.', gFile); end
S = load(gFile);  G = S.G;  pp = G.perParticipant;
tests = pp.tests(:);  nSubj = numel(tests);
fprintf('STEP 10 - group statistics | cohort %s | n = %d | Leading & Trailing analysed separately\n', COHORT, nSubj);

%% ===================== PARAMETER CATALOG =====================
% {group, key, display, unit}; matrix = pp.(group).(key) is [nSubj x nCond]. Display
% names match step9.
CAT = {
  'T1','clr_toe','Toe clearance','cm';       'T1','clr_heel','Heel clearance','cm';
  'T1','clr_min','Min clearance','cm';       'T1','lift_dist','Take-off dist','cm';
  'T1','land_dist','Landing dist','cm';
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
  'PEX','knee_pk_flex','Knee peak flexion','deg';   'PEX','ank_plant','Ankle peak plantarflexion','deg';
  'PEX','ank_dorsi','Ankle peak dorsiflexion','deg';'PEX','thigh_fwd','Thigh peak forward tilt','deg';
  'PEX','thigh_back','Thigh peak backward tilt','deg';'PEX','shank_back','Shank peak backward (heelup)','deg';
  'PEX','shank_fwd','Shank peak forward (reach)','deg';'PEX','foot_toedown','Foot peak toe-down','deg';
  'PEX','foot_toeup','Foot peak toe-up','deg';
  'PKT','hip_flexion','Hip peak timing','%GC';  'PKT','knee_angle','Knee peak timing','%GC';
  'PKT','ankle_angle','Ankle peak timing','%GC';'PKT','Thigh','Thigh peak timing','%GC';
  'PKT','Shank','Shank peak timing','%GC';      'PKT','Foot','Foot peak timing','%GC';
};

%% ===================== DESIGN: 6 obstacles (W x H), per class =====================
condName = G.condName(:)';  nC = numel(condName);        % 12 crossing conditions
[Wd, Ht, Rl] = deal(cell(1,nC));
for c = 1:nC, t = split(condName{c},'_'); Wd{c}=t{1}; Ht{c}=t{2}; Rl{c}=t{3}; end
Lcol = find(strcmp(Rl,'Leading'));  Tcol = find(strcmp(Rl,'Trailing'));   % 6 each
obList = cellfun(@(c) [Wd{c} '_' Ht{c}], num2cell(Lcol), 'uni', 0);       % obstacle order
obW = Wd(Lcol);  obH = Ht(Lcol);                                          % W/H per obstacle
wd2 = table(categorical(obW)', categorical(obH)', 'VariableNames', {'Width','Height'});

%% ===================== PER-PARAMETER STATISTICS =====================
NP = size(CAT,1);
R = struct('group',{},'key',{},'disp',{},'unit',{},'hasLevel',{},'desc',{},'pNormFail',{},'L',{},'T',{});
Yall = cell(1,NP);  Ylev = cell(1,NP);
for i = 1:NP
    grp = CAT{i,1};  key = CAT{i,2};  M = pp.(grp).(key);
    Ycr = M(:, 1:nC);  hasLevel = size(M,2) > nC;
    YL = nan(nSubj,1);  if hasLevel, YL = M(:, nC+1); end
    Yall{i} = Ycr;  Ylev{i} = YL;
    r = struct('group',grp,'key',key,'disp',CAT{i,3},'unit',CAT{i,4},'hasLevel',hasLevel);
    r.desc = [mean(Ycr,1,'omitnan'); std(Ycr,0,1,'omitnan'); sum(~isnan(Ycr),1)];
    r.pNormFail = normFail(Ycr);
    r.L = classStats(Ycr(:,Lcol), wd2, obW, obH, YL);     % LEADING only
    r.T = classStats(Ycr(:,Tcol), wd2, obW, obH, YL);     % TRAILING only
    R(i) = r;
end

% ---- FDR (Benjamini-Hochberg) across parameters, per effect, per class ----
fdr.L = fdrStruct(R, 'L');  fdr.T = fdrStruct(R, 'T');

%% ===================== OUTPUTS =====================
% SPSS-friendly: each table is its OWN single-sheet file (SPSS can't pick a sheet).
base = fullfile(outDir, sprintf('GroupStats_%s', COHORT));
oldCombined = [base '_SPSS.xlsx'];  if isfile(oldCombined), delete(oldCombined); end
writeWideLong(base, CAT, Yall, Ylev, tests, condName, Wd, Ht, Rl);
writeClassFile([base '_Results_Leading.xlsx'],  R, 'L', fdr.L);
writeClassFile([base '_Results_Trailing.xlsx'], R, 'T', fdr.T);
fprintf('Saved SPSS files (one table per file) -> %s_{Wide,Long,Descriptives,Results_Leading,Results_Trailing}.xlsx\n', base);

mdFile = fullfile(outDir, sprintf('GroupStats_%s_Report.md', COHORT));
writeReport(mdFile, R, fdr, ALPHA, COHORT, nSubj, tests);
fprintf('Saved report -> %s\n', mdFile);

printSummary(R, fdr, ALPHA);
makeFigures(figDir, R, Yall, Ylev, Wd, Ht, Rl, ALPHA, FIG_SKIP);
fprintf('Saved figures -> %s\n', figDir);
fprintf('\nDone. Statistics for %d parameters, n = %d (Leading & Trailing separate).\n', NP, nSubj);

%% ============================ functions ============================
function c = classStats(Y, wd2, obW, obH, YL)
% All tests for ONE class (Leading or Trailing) over the 6 obstacles (W x H).
    c = struct('pW',NaN,'pH',NaN,'pWH',NaN,'eta',NaN,'nUsed',0, ...
               'npH_p',NaN,'npH_W',NaN,'npW_p',NaN,'npW_r',NaN,'obs_p',NaN, ...
               'vsLevel_p',NaN,'vsLevel_dir','');
    [c.pW,c.pH,c.pWH,c.eta,c.nUsed] = rmAnova2(Y, wd2);
    [c.npH_p,c.npH_W] = friedmanFactor(Y, obH, {'H1','H2','H3'});
    [c.npW_p,c.npW_r] = wilcoxFactor(Y, obW, 'W1','W2');
    c.obs_p = friedmanOmni(Y);
    cr = mean(Y,2,'omitnan');  g = ~isnan(cr) & ~isnan(YL);
    if nnz(g) >= 4
        c.vsLevel_p = signrank(cr(g), YL(g));
        c.vsLevel_dir = tern(median(cr(g)-YL(g))>=0,'higher','lower');
    end
end

function tf = normFail(Y)
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

function [pW,pH,pWH,eta,nUsed] = rmAnova2(Y, wd2)
% Width x Height repeated-measures ANOVA (complete cases). GG p-values; partial eta^2
% for Height (primary). NaN if n<4.
    [pW,pH,pWH] = deal(NaN);  eta = NaN;
    good = all(~isnan(Y),2);  nUsed = nnz(good);
    if nUsed < 4, return; end
    Yg = Y(good,:);
    vn = arrayfun(@(k) sprintf('y%d',k), 1:size(Yg,2), 'uni',0);
    T = array2table(Yg, 'VariableNames', vn);
    try
        rm = fitrm(T, sprintf('%s-%s ~ 1', vn{1}, vn{end}), 'WithinDesign', wd2);
        a = ranova(rm, 'WithinModel', 'Width*Height');
        rn = string(a.Properties.RowNames);
        pW  = getp(a,rn,'Width');  pH = getp(a,rn,'Height');  pWH = getp(a,rn,'Width:Height');
        eta = etaSq(a, rn, 'Height');
    catch ME
        fprintf(2, 'RM-ANOVA failed: %s\n', ME.message);
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
    if ~isempty(i) && ~isempty(j), e = a.SumSq(i) / (a.SumSq(i) + a.SumSq(j)); end
end

function [p, W] = friedmanFactor(Y, lvlOf, lvls)
    p = NaN; W = NaN;
    X = nan(size(Y,1), numel(lvls));
    for L = 1:numel(lvls), X(:,L) = mean(Y(:, strcmp(lvlOf, lvls{L})), 2, 'omitnan'); end
    good = all(~isnan(X),2);  X = X(good,:);
    if size(X,1) < 4, return; end
    try
        p = friedman(X, 1, 'off');  W = friedmanChi(X) / (size(X,1)*(size(X,2)-1));
    catch
    end
end

function p = friedmanOmni(Y)
    p = NaN;  g = all(~isnan(Y),2);
    if nnz(g) >= 4
        try
            p = friedman(Y(g,:), 1, 'off');
        catch
        end
    end
end

function chi2 = friedmanChi(X)
    [n,k] = size(X);  Rk = zeros(n,k);
    for i = 1:n, [~,o] = sort(X(i,:)); Rk(i,o) = 1:k; end
    chi2 = 12/(n*k*(k+1))*sum(sum(Rk,1).^2) - 3*n*(k+1);
end

function [p, r] = wilcoxFactor(Y, lvlOf, a, b)
    p = NaN; r = NaN;
    xa = mean(Y(:, strcmp(lvlOf,a)), 2, 'omitnan');
    xb = mean(Y(:, strcmp(lvlOf,b)), 2, 'omitnan');
    g = ~isnan(xa) & ~isnan(xb);
    if nnz(g) < 4, return; end
    try
        [p,~,st] = signrank(xa(g), xb(g));
        if isfield(st,'zval') && ~isnan(st.zval), r = abs(st.zval)/sqrt(nnz(g)); end
    catch
    end
end

function F = fdrStruct(R, cls)
    F.H   = bh(arrayfun(@(r) r.(cls).npH_p,     R));
    F.W   = bh(arrayfun(@(r) r.(cls).npW_p,     R));
    F.obs = bh(arrayfun(@(r) r.(cls).obs_p,     R));
    F.vsL = bh(arrayfun(@(r) r.(cls).vsLevel_p, R));
end

function q = bh(p)
    q = nan(size(p));  idx = find(~isnan(p));  pv = p(idx);
    [s,o] = sort(pv);  m = numel(s);  adj = s .* m ./ (1:m);
    for i = m-1:-1:1, adj(i) = min(adj(i), adj(i+1)); end
    adj = min(adj,1);  out = nan(1,m);  out(o) = adj;  q(idx) = out;
end

function s = tern(c,a,b), if c, s=a; else, s=b; end, end
function pid = pidOf(grp,key), pid = matlab.lang.makeValidName(sprintf('%s_%s',grp,key)); end
function y = rnd(x), y = round(x,4); end

function writeWideLong(base, CAT, Yall, Ylev, tests, condName, Wd, Ht, Rl)
% Writes three SEPARATE single-sheet files: <base>_Wide/_Long/_Descriptives.xlsx
    NP = size(CAT,1);  nC = numel(condName);  nS = numel(tests);
    Wt = table(tests, 'VariableNames', {'Test'});
    for i = 1:NP
        pid = pidOf(CAT{i,1},CAT{i,2});  Y = Yall{i};
        for c = 1:nC, Wt.(matlab.lang.makeValidName(sprintf('%s_%s', pid, condName{c}))) = Y(:,c); end
        if any(~isnan(Ylev{i})), Wt.(matlab.lang.makeValidName([pid '_Level'])) = Ylev{i}; end
    end
    fWide = [base '_Wide.xlsx'];  if isfile(fWide), delete(fWide); end
    writetable(Wt, fWide);
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
    fLong = [base '_Long.xlsx'];  if isfile(fLong), delete(fLong); end
    writetable([L; Lv], fLong);
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
    fDesc = [base '_Descriptives.xlsx'];  if isfile(fDesc), delete(fDesc); end
    writetable(table(P,Cc,round(Mn,2),round(Sd,2),Nn,'VariableNames',{'Parameter','Condition','Mean','SD','n'}), fDesc);
end

function writeClassFile(xlsFile, R, cls, F)
    if isfile(xlsFile), delete(xlsFile); end
    nm = arrayfun(@(r) string(sprintf('%s (%s)', r.disp, r.unit)), R)';
    g = @(f) arrayfun(@(r) r.(cls).(f), R)';
    T = table(nm, g('nUsed'), rnd(g('pW')), rnd(g('pH')), rnd(g('pWH')), rnd(g('eta')), ...
              rnd(g('npH_p')), rnd(F.H'), rnd(g('npW_p')), rnd(F.W'), ...
              rnd(g('obs_p')), rnd(F.obs'), rnd(g('vsLevel_p')), rnd(F.vsL'), string(arrayfun(@(r) string(r.(cls).vsLevel_dir),R))', ...
        'VariableNames', {'Parameter','n','aov_p_Width','aov_p_Height','aov_p_WxH','eta2_Height', ...
                          'Height_p','Height_FDR','Width_p','Width_FDR','Obstacles_p','Obstacles_FDR', ...
                          'vsLevel_p','vsLevel_FDR','vsLevel_dir'});
    writetable(T, xlsFile);
end

function s = fmtp(p, q)
    if isnan(p), s = '-'; return; end
    star = '';  if q < 0.01, star = ' **'; elseif q < 0.05, star = ' *'; end
    s = sprintf('%.3f [%.3f]%s', p, q, star);
end

function s = pLbl(p)
    if isnan(p), s='-'; elseif p < 0.001, s = '<.001'; else, s = sprintf('=%.3f', p); end
end

function writeReport(mdFile, R, fdr, ALPHA, COHORT, nSubj, tests)
    fid = fopen(mdFile,'w');  if fid < 0, warning('cannot write %s', mdFile); return; end
    fprintf(fid, '# Group statistics — %s (n = %d)\n\n', COHORT, nSubj);
    fprintf(fid, 'Participants: `%s`\n\n', mat2str(tests'));
    fprintf(fid, '**Leading and Trailing limbs are analysed as SEPARATE classes** (no Role factor, no Leading-vs-Trailing comparison). Within each class: **Width**(W1=5cm, W2=15cm) × **Height**(H1,H2,H3) over the 6 obstacles; `Level_Walk` = baseline.\n\n');
    fprintf(fid, '**Tests:** non-parametric primary — Friedman (Height; and omnibus across the 6 obstacles) + Wilcoxon signed-rank (Width, and crossing vs Level). Width×Height RM-ANOVA (Greenhouse–Geisser, partial η²) alongside. FDR (Benjamini–Hochberg) across parameters per effect, within each class; α = %.2f. `*` FDR<.05, `**` FDR<.01.\n\n', ALPHA);
    classReport(fid, 'LEADING',  R, 'L', fdr.L, ALPHA);
    classReport(fid, 'TRAILING', R, 'T', fdr.T, ALPHA);
    fprintf(fid, '\n---\n*Non-parametric is the headline (n=%d). Full per-condition values in the SPSS workbook (Descriptives).*\n', nSubj);
    fclose(fid);
end

function classReport(fid, ttl, R, cls, F, ALPHA)
    fprintf(fid, '# %s limb\n\n', ttl);
    fprintf(fid, '## Significant effects (FDR-corrected)\n\n');
    sigList(fid, 'Obstacle HEIGHT',        R, F.H,   ALPHA);
    sigList(fid, 'Obstacle WIDTH',         R, F.W,   ALPHA);
    sigList(fid, 'Across obstacles (Friedman)', R, F.obs, ALPHA);
    sigList(fid, 'Crossing vs Level walk', R, F.vsL, ALPHA);
    fprintf(fid, '\n### Non-parametric — p [FDR]\n\n');
    fprintf(fid, '| Parameter | Height | Width | Across obstacles | vs Level |\n|---|---|---|---|---|\n');
    for i = 1:numel(R)
        c = R(i).(cls);
        fprintf(fid, '| %s (%s) | %s | %s | %s | %s |\n', R(i).disp, R(i).unit, ...
            fmtp(c.npH_p,F.H(i)), fmtp(c.npW_p,F.W(i)), fmtp(c.obs_p,F.obs(i)), fmtp(c.vsLevel_p,F.vsL(i)));
    end
    fprintf(fid, '\n### RM-ANOVA — p (Greenhouse–Geisser)\n\n');
    fprintf(fid, '| Parameter | n | Width | Height | W×H | η²(Height) |\n|---|--|--|--|--|--|\n');
    for i = 1:numel(R)
        c = R(i).(cls);
        fprintf(fid, '| %s | %d | %s | %s | %s | %s |\n', R(i).disp, c.nUsed, ...
            ppx(c.pW), ppx(c.pH), ppx(c.pWH), ppx(c.eta));
    end
    fprintf(fid, '\n');
end

function sigList(fid, ttl, R, q, ALPHA)
    fprintf(fid, '**%s:** ', ttl);
    k = find(q < ALPHA & ~isnan(q));
    if isempty(k), fprintf(fid, 'none.\n\n'); return; end
    [~,o] = sort(q(k));  k = k(o);
    items = arrayfun(@(i) sprintf('%s (%s) [FDR=%.3f]', R(i).disp, R(i).unit, q(i)), k, 'uni',0);
    fprintf(fid, '%s.\n\n', strjoin(items, '; '));
end

function s = ppx(x)
    if isnan(x), s = '-'; elseif x < 0.001, s = '<.001'; else, s = sprintf('%.3f', x); end
end

function printSummary(R, fdr, ALPHA)
    doClass('LEADING',  R, 'L', fdr.L, ALPHA);
    doClass('TRAILING', R, 'T', fdr.T, ALPHA);
end

function doClass(ttl, R, cls, F, ALPHA)
    fprintf('\n============== %s : significant (non-parametric, FDR) ==============\n', ttl);
    eff = {'Height',F.H; 'Width',F.W; 'Across obstacles',F.obs; 'vs Level',F.vsL};
    fld = {'npH_p','npW_p','obs_p','vsLevel_p'};
    for e = 1:size(eff,1)
        q = eff{e,2};  k = find(q < ALPHA & ~isnan(q));
        fprintf('[%s] %d sig\n', eff{e,1}, numel(k));  [~,o] = sort(q(k));
        for i = k(o)
            fprintf('   %-28s p=%.3f  FDR=%.3f\n', sprintf('%s (%s)',R(i).disp,R(i).unit), R(i).(cls).(fld{e}), q(i));
        end
    end
end

function makeFigures(figDir, R, Yall, Ylev, Wd, Ht, Rl, ALPHA, FIG_SKIP)
    ST = plotStyle();  FN = ST.font;
    % ---- combined p-value heatmap: Leading cols | Trailing cols ----
    NP = numel(R);
    cols = {'npH_p','npW_p','obs_p','vsLevel_p'};  clab = {'Height','Width','Obst','vsLvl'};
    Pm = nan(NP, 8);
    for i=1:NP
        for j=1:4, Pm(i,j)=R(i).L.(cols{j}); Pm(i,j+4)=R(i).T.(cols{j}); end
    end
    f1 = figure('Color','w','Position',[50 50 1000 1020]);  ax1 = axes(f1);
    imagesc(ax1, -log10(Pm), 'AlphaData', ~isnan(Pm));  colormap(ax1, flipud(hot));
    cb = colorbar(ax1);  cb.Label.String='-log_{10}(p)';  cb.Label.FontName=FN;  cb.Label.FontSize=ST.szLabel;
    set(ax1,'XTick',1:8,'XTickLabel',[strcat('L:',clab) strcat('T:',clab)], ...
        'YTick',1:NP,'YTickLabel',arrayfun(@(r)sprintf('%s (%s)',r.disp,r.unit),R,'uni',0), ...
        'FontName',FN,'FontSize',9,'FontWeight','bold','TickLabelInterpreter','none','LineWidth',ST.boxWidth);
    hold(ax1,'on');  clim(ax1,[0 max(3,max(-log10(Pm(:)),[],'omitnan'))]);  xline(ax1,4.5,'k','LineWidth',2);
    for i=1:NP, for j=1:8, if ~isnan(Pm(i,j)) && Pm(i,j)<ALPHA, text(ax1,j,i,'*','HorizontalAlignment','center','Color',[0 .6 1],'FontWeight','bold','FontSize',13); end, end, end
    title(ax1,sprintf('Significance heatmap  (Leading | Trailing;  * p<%.2f uncorrected)',ALPHA),'FontName',FN,'FontSize',ST.szTitle,'FontWeight','bold');
    exportgraphics(f1, fullfile(figDir,'pvalue_heatmap.png'), 'Resolution', ST.pngDPI);
    % ---- distribution figures: 6 obstacles, Leading(blue)/Trailing(orange), per-class sig ----
    Ob = cellfun(@(w,h)[w '_' h], Wd, Ht, 'uni',0);  obList = unique(Ob,'stable');
    codes = cellfun(@(o)[o(2) o(5)], obList, 'uni',0);
    grps = unique({R.group},'stable');
    for gi = 1:numel(grps)
        idx = find(strcmp({R.group},grps{gi}) & ~ismember({R.key},FIG_SKIP));  if isempty(idx), continue; end
        nP = numel(idx);  nc = min(2,nP);  nr = ceil(nP/nc);
        f = figure('Color','w','Position',[30 30 740*nc 400*nr]);
        tl = tiledlayout(f, nr, nc, 'TileSpacing','compact','Padding','compact');  hbRef = [];
        for a = 1:nP
            ri = idx(a);  ax = nexttile(tl);
            hb = drawObstaclePanel(ax, Yall{ri}, Ob, obList, codes, Rl, Ylev{ri}, R(ri).L.obs_p, R(ri).T.obs_p, ST, sprintf('%s (%s)',R(ri).disp,R(ri).unit));
            if a==1, hbRef = hb; end
        end
        if ~isempty(hbRef)
            lg = legend(hbRef, {'Leading','Trailing','Level walk'}, 'Orientation','horizontal','FontName',FN,'FontSize',ST.szLegend);
            lg.Layout.Tile = 'north';
        end
        title(tl, sprintf('%s   (x = obstacle W-H;  colored * = that class differs from level walk: * p<.05 ** p<.01 *** p<.001;  outliers hidden)',grps{gi}), ...
            'FontName',FN,'FontSize',ST.szSub,'FontWeight','bold');
        exportgraphics(tl, fullfile(figDir, sprintf('dist_%s.png', grps{gi})), 'Resolution', ST.pngDPI);
    end
end

function hb = drawObstaclePanel(ax, Y, Ob, obList, codes, Rl, YL, obsPL, obsPT, ST, ttl)
    hold(ax,'on'); box(ax,'on');
    roles = {'Leading','Trailing'};  cols = {ST.colLead, ST.colTrail};  nO = numel(obList);
    off = [-0.19 0.19];  hb = gobjects(1,3);  inAll = [];
    for o = 1:nO
        for rr = 1:2
            v = Y(:, strcmp(Ob,obList{o}) & strcmp(Rl,roles{rr}));  v = v(~isnan(v(:)));
            [h,inl] = drawBox(ax, o+off(rr), 0.16, v, cols{rr}, ST);  inAll = [inAll; inl(:)]; %#ok<AGROW>
            if o==1, hb(rr) = h; end
        end
    end
    hb(3) = plot(ax, NaN, NaN, '--', 'Color', ST.colLevel, 'LineWidth', ST.levelW);
    if any(~isnan(YL)), yline(ax, median(YL,'omitnan'), '--', 'Color', ST.colLevel, 'LineWidth', ST.levelW); end
    lo = min(inAll);  hi = max(inAll);  if ~isfinite(lo), lo=0; hi=1; end
    rng = max(hi-lo, eps);  ytop = hi + 0.09*rng;
    % per-class vs-level stars over each obstacle (blue=Leading, orange=Trailing)
    if any(~isnan(YL))
        for o = 1:nO
            for rr = 1:2
                v = mean(Y(:, strcmp(Ob,obList{o}) & strcmp(Rl,roles{rr})), 2, 'omitnan');
                s = sigStar(pairedP(v, YL));
                if ~strcmp(s,'ns'), text(ax, o+off(rr), ytop, s, 'HorizontalAlignment','center', ...
                    'Color', cols{rr}, 'FontName',ST.font,'FontSize',ST.szTick-1,'FontWeight','bold'); end
            end
        end
    end
    set(ax, 'XTick',1:nO,'XTickLabel',codes,'FontName',ST.font,'FontSize',ST.szTick,'FontWeight','bold', ...
        'LineWidth',ST.boxWidth,'XColor',[.15 .15 .15],'YColor',[.15 .15 .15]);
    xlim(ax,[0.5 nO+0.5]);  ylim(ax,[lo-0.08*rng, ytop+0.07*rng]);
    tt = sprintf('%s   [obst L:p%s%s  T:p%s%s]', ttl, pLbl(obsPL), sigStar(obsPL), pLbl(obsPT), sigStar(obsPT));
    title(ax, tt, 'FontName',ST.font,'FontSize',ST.szTitle-2,'FontWeight','bold','Interpreter','none');
    xlabel(ax, 'Obstacle (Width-Height)', 'FontName',ST.font,'FontSize',ST.szLabel,'FontWeight','bold');
end

function [h, inl] = drawBox(ax, x, w, v, col, ST)
    h = fill(ax, [x-w x+w x+w x-w], [0 0 0 0], col);  inl = [];
    if isempty(v), return; end
    q = quantile(v, [.25 .5 .75]);  iqr = q(3)-q(1);
    inl = v(v >= q(1)-1.5*iqr & v <= q(3)+1.5*iqr);  if isempty(inl), inl = v; end
    wl = min(inl);  wu = max(inl);
    set(h, 'XData',[x-w x+w x+w x-w], 'YData',[q(1) q(1) q(3) q(3)], 'FaceColor',col,'FaceAlpha',0.35,'EdgeColor',col,'LineWidth',1.4);
    plot(ax, [x-w x+w], [q(2) q(2)], 'Color',col,'LineWidth',2.2);
    plot(ax, [x x], [wl q(1)], 'Color',col,'LineWidth',ST.errW);
    plot(ax, [x x], [q(3) wu], 'Color',col,'LineWidth',ST.errW);
    plot(ax, x+(rand(numel(inl),1)-.5)*w*0.9, inl, 'o','MarkerSize',3.5,'MarkerFaceColor',col*0.7+0.3,'MarkerEdgeColor',col*0.6,'LineWidth',0.3);
end

function p = pairedP(a, b)
    g = ~isnan(a) & ~isnan(b);  p = NaN;
    if nnz(g) >= 4
        try
            p = signrank(a(g), b(g));
        catch
        end
    end
end

function s = sigStar(p)
    if isnan(p), s = 'ns'; elseif p < 0.001, s = '***'; elseif p < 0.01, s = '**'; ...
    elseif p < 0.05, s = '*'; else, s = 'ns'; end
end
