function crossing_ml_figures(want)
% CROSSING_ML_FIGURES  Draws every ML figure in the step 9 plot template.
%
%   crossing_ml_figures              % redraw all ML figures from the saved results (seconds)
%   crossing_ml_figures('haptic')    % one group: main, followup, limbs, settings, explore, device,
%                                    % stream, realworld, lateral, validate, haptic, story_map,
%                                    % story_person, story_strategy, story_embed, stats, robust, params,
%                                    % confusion
%
% The analyses (crossing_ml_*.m) save the numbers behind their figures in
% Results/ML Models/MATLAB/figdata/<group>.mat (mlTools.figures) and call this function for their
% own group, so a full analysis run also draws its figures. Run it alone to restyle or redraw the
% figures without recomputing anything.
%
% Template = Analysis/step09_group_crossing_analysis.m ("PLOT STYLE (template)"): Arial; layout
% title 18 bold with a grey 12-pt subtitle; panel titles and axis labels 16 bold; tick labels
% 13 bold; legend 14 in a box; 2-pt axes box, no grid; bars with a dark 0.8-pt outline and
% 1.2-pt error bars; blue = leading limb, orange = trailing limb, red dashed = level walk; PNG at
% 300 dpi of the tiled layout. Added for the ML figures: green = both limbs / the two-foot device,
% grey = generic model (level-walk calibration), purple = person scaling, grey dashed = chance.

here = fileparts(mfilename('fullpath'));
out = fullfile(fileparts(fileparts(here)), 'Results', 'ML Models', 'MATLAB');
groups = {'main', 'followup', 'limbs', 'settings', 'explore', 'device', 'stream', 'realworld', 'lateral', ...
          'validate', 'haptic', 'story_map', 'story_person', 'story_strategy', 'story_embed', 'stats', 'robust', 'params', 'confusion'};
if nargin < 1 || isempty(want), want = groups; end
want = cellstr(want);
for k = 1:numel(want)
    f = fullfile(out, 'figdata', [want{k} '.mat']);
    if ~isfile(f)
        warning('crossing_ml_figures:nodata', 'no saved results for %s (%s): run its analysis first', want{k}, f);
        continue;
    end
    S = load(f);
    switch want{k}
        case 'main',           figFeatureSets(out, S);  figConfusion(out, S);  figParticipants(out, S);
        case 'followup',       figCueing(out, S);  figLearning(out, S);
        case 'limbs',          figLimbs(out, S);
        case 'settings',       figSettings(out, S);
        case 'explore',        figExplore(out, S);
        case 'device',         figDevice(out, S);
        case 'stream',         figStream(out, S);
        case 'realworld',      figRealworld(out, S);
        case 'lateral',        figLateral(out, S);
        case 'validate',       figValidate(out, S);
        case 'haptic',         figHaptic(out, S);  figHapticCurves(out, S);
        case 'story_map',      figStoryMap(out, S);
        case 'story_person',   figStoryPerson(out, S);
        case 'story_strategy', figStoryStrategy(out, S);
        case 'story_embed',    figStoryEmbed(out, S);
        case 'stats',          figStats(out, S);
        case 'robust',         figRobust(out, S);
        case 'params',         figParams(out, S);  figParamsClear(out, S);
        case 'confusion',      figConfusionSelf(out, S);
        otherwise, error('crossing_ml_figures:group', 'unknown figure group %s', want{k});
    end
    fprintf('Figures drawn: %s\n', want{k});
end
end

%% ========================================================================
%  crossing_ml_matlab: feature sets, confusion, participants, cueing, learning curve, limbs, settings
%% ========================================================================
function figFeatureSets(out, S)
ST = tmpl();  M = S.M;
P = M(strcmp({M.normalization}, 'calibrated') & strcmp({M.model}, 'logreg') & strcmp({M.rows}, S.include));
order = unique({P.features}, 'stable');  n = numel(order);  yy = (n:-1:1)';
[~, tl] = newFig(1400, 34 * n + 250, 1, 2);
tasks = {'height', 'Height (3 classes)'; 'width', 'Width (2 classes)'};
for t = 1:2
    ax = tile(tl);
    v = zeros(n, 1);  b95 = v;  ch = 0;
    for i = 1:n
        r = P(strcmp({P.task}, tasks{t,1}) & strcmp({P.features}, order{i}));
        v(i) = 100 * r.bal_acc;  b95(i) = 100 * r.null95;  ch = 100 * r.chance;
    end
    hbars(ax, yy, v, limbColours(order));
    for i = 1:n
        plot(ax, [b95(i) b95(i)], yy(i) + [-0.45 0.45], '-', 'Color', 'k', 'LineWidth', 2.6);
        valText(ax, max(v(i), b95(i)) + 1.5, yy(i), sprintf('%.0f', v(i)), 'VerticalAlignment', 'middle');
    end
    refLine(ax, ch, 'x', '');
    xlim(ax, [0 100]);  ylim(ax, [0.4 n + 0.6]);
    if t == 1, set(ax, 'YTick', 1:n, 'YTickLabel', flip(order)); else, set(ax, 'YTick', 1:n, 'YTickLabel', []); end
    lbl(ax, 'balanced accuracy (%)', '');
    ttl(ax, tasks{t,2});
end
h = [keyPatch(ax, ST.both), keyPatch(ax, ST.lead), keyPatch(ax, ST.trail), ...
     plot(ax, NaN, NaN, '-', 'Color', 'k', 'LineWidth', 2.6), plot(ax, NaN, NaN, '--', 'Color', ST.ref, 'LineWidth', ST.refW)];
lg = leg(ax, h, {'both limbs', 'leading limb', 'trailing limb', 'permutation 95th percentile', 'chance'}, 'Orientation', 'horizontal');
lg.Layout.Tile = 'north';
layoutTitle(tl, 'Which feature set carries the obstacle? (generic model)', ...
    'logistic regression on level-walk-calibrated Dot features; balanced accuracy for a participant left out of training');
saveFig(tl, out, 'fig_feature_sets.png');
end

function figConfusion(out, S)
ST = tmpl();
keys = {'height|all', 'Height, all features'; 'height|lead only', 'Height, leading limb only'; 'width|all', 'Width, all features'};
[~, tl] = newFig(1400, 560, 1, 3);
cm = seqMap(ST.lead);
for k = 1:3
    c = S.conf(strcmp({S.conf.key}, keys{k,1}));
    ax = tile(tl);
    pc = 100 * c.cm ./ sum(c.cm, 2);  nl = numel(c.lab);
    imagesc(ax, pc, [0 100]);  colormap(ax, cm);
    for i = 1:nl
        for j = 1:nl
            col = ST.ink;  if pc(i,j) > 55, col = [1 1 1]; end
            text(ax, j, i, sprintf('%.0f%%\n(n = %d)', pc(i,j), c.cm(i,j)), 'HorizontalAlignment', 'center', ...
                'FontName', ST.font, 'FontSize', 13, 'FontWeight', 'bold', 'Color', col);
        end
    end
    axis(ax, 'image');
    set(ax, 'YDir', 'reverse', 'XTick', 1:nl, 'XTickLabel', c.lab, 'YTick', 1:nl, 'YTickLabel', c.lab, 'TickLength', [0 0]);
    if k == 1, lbl(ax, 'predicted', 'true class'); else, lbl(ax, 'predicted', ''); end
    ttl(ax, keys{k,2});
end
layoutTitle(tl, 'Confusion matrices (generic model, logistic regression)', ...
    'cell = % of the true class (row) and number of crossings; every participant tested unseen');
saveFig(tl, out, 'fig_confusion.png');
end

function figConfusionSelf(out, S)
% Generic (top) vs person-scaled (bottom) confusion matrices of the same logistic model (crossing_ml_confusion.m).
ST = tmpl();
keys = {'height|all', 'height|lead only', 'width|all'};
nm = {'Generic', ST.lead;  'Person scaling', ST.person};          % colour maps: fig_confusion blue, person purple
[~, tl] = newFig(1400, 1060, 2, 3);
for n = 1:2
    for k = 1:3
        c = S.conf(strcmp({S.conf.key}, keys{k}) & strcmp({S.conf.norm}, S.norms{n,1}));
        ax = tile(tl);
        pc = 100 * c.cm ./ sum(c.cm, 2);  nl = numel(c.lab);
        imagesc(ax, pc, [0 100]);  colormap(ax, seqMap(nm{n,2}));
        for i = 1:nl
            for j = 1:nl
                col = ST.ink;  if pc(i,j) > 55, col = [1 1 1]; end
                text(ax, j, i, sprintf('%.0f%%\n(n = %d)', pc(i,j), c.cm(i,j)), 'HorizontalAlignment', 'center', ...
                    'FontName', ST.font, 'FontSize', 13, 'FontWeight', 'bold', 'Color', col);
            end
        end
        axis(ax, 'image');
        set(ax, 'YDir', 'reverse', 'XTick', 1:nl, 'XTickLabel', c.lab, 'YTick', 1:nl, 'YTickLabel', c.lab, 'TickLength', [0 0]);
        if k == 1, lbl(ax, 'predicted', 'true class'); else, lbl(ax, 'predicted', ''); end
        ttl(ax, sprintf('%s\n%s, %.1f%%', nm{n,1}, c.title, 100 * c.bal));
    end
end
layoutTitle(tl, 'Confusion matrices: generic model vs person scaling (logistic regression)', ...
    'cell = % of the true class (row) and number of crossings; title = balanced accuracy; every participant tested unseen');
saveFig(tl, out, 'fig_confusion_self.png');
end

function figParticipants(out, S)
ST = tmpl();  M = S.M;  P = 101:110;
nm = {'all', 'lead only', 'trail only'};  cols = [ST.both; ST.lead; ST.trail];
V = zeros(numel(P), 3);
for k = 1:3
    r = M(strcmp({M.task}, 'height') & strcmp({M.features}, nm{k}) & strcmp({M.normalization}, 'calibrated') & ...
        strcmp({M.model}, 'logreg') & strcmp({M.rows}, S.include));
    V(:, k) = 100 * r.acc(:);
end
[~, tl] = newFig(1300, 600, 1, 1);
ax = tile(tl);
b = vbars(ax, V, cols);
refLine(ax, 100/3, 'y', '');
set(ax, 'XTick', 1:numel(P), 'XTickLabel', arrayfun(@num2str, P, 'UniformOutput', false));
ylim(ax, [0 105]);  xlim(ax, [0.4 numel(P) + 0.6]);
lbl(ax, 'participant (tested unseen)', 'accuracy (%)');
lg = leg(ax, b, {'both limbs (all features)', 'leading limb only', 'trailing limb only'}, 'Orientation', 'horizontal');
lg.Layout.Tile = 'north';
layoutTitle(tl, 'Obstacle height for each participant (generic model)', ...
    'logistic regression on level-walk-calibrated Dot features; dashed = chance (33%)');
saveFig(tl, out, 'fig_participants.png');
end

function figCueing(out, S)
ST = tmpl();  TR = S.TR;  x = -TR.ms;
[~, tl] = newFig(1300, 650, 1, 1);
ax = tile(tl);
fill(ax, [x; flipud(x)], 100 * [TR.level_logreg_lo; flipud(TR.level_logreg_hi)], ST.lead, 'FaceAlpha', 0.15, 'EdgeColor', 'none');
plot(ax, x, 100 * TR.level_logreg, '-o', 'Color', ST.lead, 'LineWidth', ST.lineW, 'MarkerSize', 8, ...
    'MarkerFaceColor', ST.lead, 'MarkerEdgeColor', 'w');
for i = [1 6 11]          % first label centred; the others end left of their point, clear of the event lines
    if i == 1, xt = x(i); ha = 'center'; else, xt = x(i) - 12; ha = 'right'; end
    valText(ax, xt, 100 * TR.level_logreg_hi(i) + 3, sprintf('%d%% of swing', TR.cut(i)), 'HorizontalAlignment', ha);
end
evLine(ax, S.ev(1), 'leading foot apex');
evLine(ax, S.ev(2), 'leading landing');
evLine(ax, 0, 'trailing toe lift-off');
refLine(ax, 100/3, 'y', 'chance');
ylim(ax, [20 100]);  xlim(ax, [min(x) - 60, 60]);
lbl(ax, 'time relative to the trailing toe lift-off (ms, median)', 'balanced accuracy (%)');
layoutTitle(tl, 'How early is the height known? Leading-limb data up to each moment', ...
    'generic model (logistic regression); band = 95% participant-bootstrap CI; labels = % of the leading swing');
saveFig(tl, out, 'fig_cueing_time.png');
end

function figLearning(out, S)
ST = tmpl();  LC = S.LC;  n = 2:9;
names = regexprep(S.lcNames, '^lead ', 'leading ');  names(strcmp(names, 'all')) = {'all features (both limbs)'};
cols = [ST.both; ST.lead; 0.45 * ST.lead; ST.lead + 0.55 * (1 - ST.lead)];  mk = {'o', 's', 'd', '^'};
[~, tl] = newFig(1300, 700, 1, 1);
ax = tile(tl);
h = gobjects(numel(names), 1);
for m = 1:numel(names)
    fill(ax, [n fliplr(n)], 100 * [LC.p10(m,:) fliplr(LC.p90(m,:))], cols(m,:), 'FaceAlpha', 0.10, 'EdgeColor', 'none');
    h(m) = plot(ax, n, 100 * LC.mean(m,:), ['-' mk{m}], 'Color', cols(m,:), 'LineWidth', ST.lineW, 'MarkerSize', 9, ...
        'MarkerFaceColor', cols(m,:), 'MarkerEdgeColor', 'w');
end
refLine(ax, 100/3, 'y', 'chance');
xlim(ax, [1.8 9.2]);  ylim(ax, [20 min(100, 5 * ceil(max(100 * LC.p90(:)) / 5) + 5)]);  set(ax, 'XTick', n);
lbl(ax, 'number of training participants', 'balanced accuracy (%)');
lg = leg(ax, h, names, 'NumColumns', 2);  lg.Layout.Tile = 'north';
layoutTitle(tl, 'Learning curve: does more training data help? (height, generic model)', ...
    'logistic regression; band = 10th-90th percentile over random training sets; tested on the participants left out');
saveFig(tl, out, 'fig_learning_curve.png');
end

function figLimbs(out, S)
ST = tmpl();  A = S.A;
col = struct('raw', ST.raw, 'level', ST.generic, 'self', ST.person);
panels = {'height', 'A', 'Height (3 classes)'; 'width', 'A', 'Width (2 classes)'; '6 obstacles', 'A', '6 obstacles'; ...
          'obstacle vs level', 'C', 'Obstacle or level walk?'};
[~, tl] = newFig(1500, 950, 2, 3);
for p = 1:4
    ax = tile(tl);
    d = A(strcmp({A.block}, panels{p,2}) & strcmp({A.task}, panels{p,1}));
    norms = intersect({'raw', 'level', 'self'}, unique({d.normalization}), 'stable');
    nn = numel(norms);  w = 0.84 / nn;
    for i = 1:nn
        x = (1:3) + (i - (nn + 1) / 2) * w;
        dd = arrayfun(@(l) d(strcmp({d.normalization}, norms{i}) & strcmp({d.limb}, l{1})), {'lead', 'trail', 'fusion'});
        v = 100 * [dd.bal_acc];
        bar(ax, x, v, w, 'FaceColor', col.(norms{i}), 'EdgeColor', ST.edge, 'LineWidth', ST.barEdgeW);
        errorbar(ax, x, v, v - 100 * [dd.ci_lo], 100 * [dd.ci_hi] - v, 'LineStyle', 'none', 'Color', ST.ink, ...
            'LineWidth', ST.errW, 'CapSize', 4);
    end
    refLine(ax, 100 * d(1).chance, 'y', '');
    set(ax, 'XTick', 1:3, 'XTickLabel', {'leading', 'trailing', 'fusion'});  ylim(ax, [0 105]);  xlim(ax, [0.45 3.55]);
    if p == 1 || p == 4, lbl(ax, '', 'balanced accuracy (%)'); end
    ttl(ax, panels{p,3});
end
ax = tile(tl);
d = A(strcmp({A.block}, 'B'));  nn = {'raw', 'level', 'self'};
for i = 1:3
    r = d(strcmp({d.normalization}, nn{i}));
    bar(ax, i, 100 * r.bal_acc, 0.7, 'FaceColor', col.(nn{i}), 'EdgeColor', ST.edge, 'LineWidth', ST.barEdgeW);
    errorbar(ax, i, 100 * r.bal_acc, 100 * (r.bal_acc - r.ci_lo), 100 * (r.ci_hi - r.bal_acc), 'Color', ST.ink, ...
        'LineWidth', ST.errW, 'CapSize', 4);
end
refLine(ax, 50, 'y', '');
set(ax, 'XTick', 1:3, 'XTickLabel', {'raw', 'generic', 'person'});  ylim(ax, [0 105]);  xlim(ax, [0.4 3.6]);
ttl(ax, 'Leading or trailing limb?');
lg = leg(ax, [keyPatch(ax, ST.raw), keyPatch(ax, ST.generic), keyPatch(ax, ST.person)], ...
    {'raw features', 'generic (level-walk calibration)', 'person scaling'}, 'Orientation', 'horizontal');
lg.Layout.Tile = 'north';
layoutTitle(tl, 'Separate leading and trailing limb models and their fusion (logistic regression)', ...
    'balanced accuracy for a participant left out of training; whiskers = 95% participant-bootstrap CI; dashed = chance');
saveFig(tl, out, 'fig_limbs.png');
end

function figSettings(out, S)
ST = tmpl();
d = S.SR(strcmp({S.SR.model}, 'forest'));  n = numel(d);  yy = (n:-1:1)';
v = 100 * [d.bal]';  lo = 100 * [d.lo]';  hi = 100 * [d.hi]';
[~, tl] = newFig(1500, max(720, 34 * n + 250), 1, 2);
ax = tile(tl);
hbars(ax, yy, v, limbColours({d.features}));
errorbar(ax, v, yy, v - lo, hi - v, 'horizontal', 'LineStyle', 'none', 'Color', ST.ink, 'LineWidth', ST.errW, 'CapSize', 4);
for i = 1:n, valText(ax, hi(i) + 1.5, yy(i), sprintf('%.0f', v(i)), 'VerticalAlignment', 'middle'); end
refLine(ax, 100/3, 'x', '');
set(ax, 'YTick', 1:n, 'YTickLabel', flip({d.features}));  xlim(ax, [0 110]);  ylim(ax, [0.4 n + 0.6]);
lbl(ax, 'balanced accuracy (%)', '');
ttl(ax, 'Which segment and limb?');
leg(ax, [keyPatch(ax, ST.both), keyPatch(ax, ST.lead), keyPatch(ax, ST.trail)], {'both limbs', 'leading', 'trailing'}, ...
    'Location', 'southoutside', 'Orientation', 'horizontal');
ax = tile(tl);
TR = S.TR;  x = -TR.ms;  nm = {'level', 'self'};  cc = [ST.generic; ST.person];  h = gobjects(2, 1);
for i = 1:2
    k = [nm{i} '_forest'];
    fill(ax, [x; flipud(x)], 100 * [TR.([k '_lo']); flipud(TR.([k '_hi']))], cc(i,:), 'FaceAlpha', 0.15, 'EdgeColor', 'none');
    h(i) = plot(ax, x, 100 * TR.(k), '-o', 'Color', cc(i,:), 'LineWidth', ST.lineW, 'MarkerSize', 8, ...
        'MarkerFaceColor', cc(i,:), 'MarkerEdgeColor', 'w');
end
lab = {'leading toe-off', 0; 'leading apex (50%)', 50; 'leading landing', 100};
for i = 1:3, evLine(ax, -TR.ms(TR.cut == lab{i,2}), lab{i,1}, '-', 'bottom'); end   % labels below the curves
evLine(ax, 0, 'trailing toe lift-off', '-', 'bottom');
refLine(ax, 100/3, 'y', '');
ylim(ax, [20 100]);  xlim(ax, [min(x) - 60, 60]);
lbl(ax, 'time relative to the trailing toe lift-off (ms, median)', 'balanced accuracy (%)');
ttl(ax, 'When is the height known?');
leg(ax, h, {'generic model', 'person scaling'}, 'Location', 'northwest');
layoutTitle(tl, 'Obstacle height by body segment and over time (random forest)', ...
    'left: person scaling, 95% participant-bootstrap CI, dashed = chance; right: leading-limb data up to each moment, band = 95% CI');
saveFig(tl, out, 'fig_settings.png');
end

%% ========================================================================
%  crossing_ml_explore, crossing_ml_device, crossing_ml_stream, crossing_ml_realworld, crossing_ml_lateral
%% ========================================================================
function figExplore(out, S)
ST = tmpl();  R = S.R;
q = @(sec, feat, limb, norm, model) R(find(strcmp({R.sec}, sec) & strcmp({R.target}, 'height') & strcmp({R.feat}, feat) & ...
    strcmp({R.limb}, limb) & strcmp({R.norm}, norm) & strcmp({R.model}, model), 1));
x3 = R(strcmp({R.sec}, 'X3'));  [~, i3] = max([x3.bal]);
x2 = R(strcmp({R.sec}, 'X2'));  [~, i2] = max([x2.bal]);
light = ST.person + 0.45 * (1 - ST.person);
items = {'summary features', q('X1', 'summary', 'lead', 'level', 'logreg'), ST.generic;
         'shape features', q('X1', 'shape', 'lead', 'level', 'logreg'), ST.generic;
         'nested selection, generic', q('X7', 'nested generic', 'chosen', 'chosen', 'chosen'), ST.generic;
         'generic + ranking in thirds', x3(i3), light;
         'person scaling, best model', x2(i2), ST.person;
         'nested selection, all settings', q('X7', 'nested all', 'chosen', 'chosen', 'chosen'), ST.person};
[~, tl] = newFig(1500, 660, 1, 3);
ax = tile(tl, [1 2]);
n = size(items, 1);  yy = (n:-1:1)';
for i = 1:n
    r = items{i,2};
    barh(ax, yy(i), 100 * r.bal, 0.7, 'FaceColor', items{i,3}, 'EdgeColor', ST.edge, 'LineWidth', ST.barEdgeW);
    errorbar(ax, 100 * r.bal, yy(i), 100 * (r.bal - r.lo), 100 * (r.hi - r.bal), 'horizontal', 'Color', ST.ink, ...
        'LineWidth', ST.errW, 'CapSize', 4);
    plot(ax, 100 * r.worst, yy(i), 'd', 'MarkerSize', 11, 'MarkerFaceColor', 'w', 'MarkerEdgeColor', ST.ink, 'LineWidth', 1.6);
    valText(ax, 100 * r.hi + 1.5, yy(i), sprintf('%.0f%%', 100 * r.bal), 'VerticalAlignment', 'middle');
end
refLine(ax, 100/3, 'x', '');
set(ax, 'YTick', 1:n, 'YTickLabel', flip(items(:,1)));  xlim(ax, [0 108]);  ylim(ax, [0.4 n + 0.6]);
lbl(ax, 'balanced accuracy (%)', '');
ttl(ax, 'What each idea adds');
hk = [keyPatch(ax, ST.generic), keyPatch(ax, light), keyPatch(ax, ST.person), ...
      plot(ax, NaN, NaN, 'd', 'MarkerSize', 11, 'MarkerFaceColor', 'w', 'MarkerEdgeColor', ST.ink, 'LineWidth', 1.6)];
lg = leg(ax, hk, {'generic', 'ranks the person''s own crossings', 'person scaling', 'worst participant'}, 'Orientation', 'horizontal');
lg.Layout.Tile = 'north';
ax = tile(tl);
nm = {'summary', 'shape', 'summary_shape'};  cc = [ST.lead + 0.55 * (1 - ST.lead); ST.lead; 0.45 * ST.lead];  mk = {'o', 's', 'd'};
h = gobjects(3, 1);
for i = 1:3
    v = S.FS(strcmp({S.FS.feat}, nm{i}));
    h(i) = plot(ax, [v.k], 100 * [v.m], ['-' mk{i}], 'Color', cc(i,:), 'LineWidth', ST.lineW, 'MarkerSize', 9, ...
        'MarkerFaceColor', cc(i,:), 'MarkerEdgeColor', 'w');
end
refLine(ax, 100/3, 'y', 'chance');
set(ax, 'XTick', 0:3);  ylim(ax, [20 100]);  xlim(ax, [-0.2 3.2]);
lbl(ax, 'labelled crossings per height', 'balanced accuracy (%)');
ttl(ax, 'Short personal calibration');
leg(ax, h, {'summary', 'shape', 'summary + shape'}, 'Location', 'northwest');
layoutTitle(tl, 'New ideas for recognising the obstacle height', ...
    ['left: bar = all participants with 95% participant-bootstrap CI; right: leading-limb features, generic model + k labelled ' ...
     'crossings of the new person; dashed = chance']);
saveFig(tl, out, 'fig_explore.png');
end

function figDevice(out, S)
ST = tmpl();  R1 = S.R1;  B = S.B;  CV = S.CV;  LC = S.LC;
[~, tl] = newFig(1700, 1040, 2, 3);
% sensors
ax = tile(tl);
n = numel(R1);  yy = (n:-1:1)';  v = 100 * [R1.b]';
cc = repmat(ST.generic, n, 1);  cc(strcmp({R1.name}, '2 foot IMUs'), :) = ST.both;
hbars(ax, yy, v, cc);
errorbar(ax, v, yy, v - 100 * [R1.lo]', 100 * [R1.hi]' - v, 'horizontal', 'LineStyle', 'none', 'Color', ST.ink, ...
    'LineWidth', ST.errW, 'CapSize', 4);
for i = 1:n, valText(ax, 100 * R1(i).hi + 1.5, yy(i), sprintf('%.0f', v(i)), 'VerticalAlignment', 'middle'); end
refLine(ax, 100/3, 'x', '');
set(ax, 'YTick', 1:n, 'YTickLabel', flip({R1.name}));  xlim(ax, [0 112]);  ylim(ax, [0.4 n + 0.6]);
lbl(ax, 'accuracy (%)', '');
ttl(ax, 'Which sensors?');
% confidence
ax = tile(tl);
plot(ax, 100 * CV(:,2), 100 * CV(:,3), '-o', 'Color', ST.both, 'LineWidth', ST.lineW, 'MarkerSize', 9, ...
    'MarkerFaceColor', ST.both, 'MarkerEdgeColor', 'w');
for i = 1:size(CV, 1)
    if CV(i,1) == 0, s = 'always'; else, s = sprintf('p \\geq %.1f', CV(i,1)); end
    valText(ax, 100 * CV(i,2), 100 * CV(i,3) - 0.4, s, 'HorizontalAlignment', 'left', 'VerticalAlignment', 'top');
end
set(ax, 'XDir', 'reverse');  xlim(ax, [30 105]);  ylim(ax, [85 100]);
lbl(ax, 'crossings answered (%)', 'accuracy on them (%)');
ttl(ax, 'Answer only when confident');
% more participants
ax = tile(tl);
fill(ax, [LC(:,1); flipud(LC(:,1))], 100 * [LC(:,3); flipud(LC(:,4))], ST.both, 'FaceAlpha', 0.15, 'EdgeColor', 'none');
plot(ax, LC(:,1), 100 * LC(:,2), '-o', 'Color', ST.both, 'LineWidth', ST.lineW, 'MarkerSize', 9, ...
    'MarkerFaceColor', ST.both, 'MarkerEdgeColor', 'w');
refLine(ax, 100/3, 'y', 'chance');
ylim(ax, [20 100]);  set(ax, 'XTick', LC(:,1));  xlim(ax, [min(LC(:,1)) - 0.3, max(LC(:,1)) + 0.3]);
lbl(ax, 'training participants', 'accuracy (%)');
ttl(ax, 'More participants?');
% calibration
ax = tile(tl, 4, [1 3]);
n = numel(B);  Br = B(end:-1:1);  v = 100 * [Br.b]';
cc = repmat(ST.generic, n, 1);
for i = 1:n
    if contains(Br(i).what, {'unlabelled', 'scaling from'}), cc(i,:) = ST.person;
    elseif contains(Br(i).what, 'labelled'), cc(i,:) = ST.teal; end
end
hbars(ax, (1:n)', v, cc);
for i = 1:n, valText(ax, v(i) + 1.2, i, sprintf('%.0f%%', v(i)), 'VerticalAlignment', 'middle'); end
refLine(ax, 100/3, 'x', '');
set(ax, 'YTick', 1:n, 'YTickLabel', shortCal({Br.what}));  xlim(ax, [0 105]);  ylim(ax, [0.4 n + 0.6]);
lbl(ax, 'accuracy for a participant left out of training (%)', '');
ttl(ax, 'How much does the device need to know about the new user?');
lg = leg(ax, [keyPatch(ax, ST.generic), keyPatch(ax, ST.teal), keyPatch(ax, ST.person), keyPatch(ax, ST.both)], ...
    {'nothing (generic)', 'labelled crossings', 'unlabelled crossings', 'two foot IMUs (device)'}, 'Orientation', 'horizontal');
lg.Layout.Tile = 'north';
layoutTitle(tl, 'What would a wearable device need? (obstacle height, 3 classes)', ...
    'person scaling unless stated; accuracy for an unseen participant; whiskers / band = 95% participant-bootstrap CI or min-max; dashed = chance');
saveFig(tl, out, 'fig_device.png');
end

function figStream(out, S)
ST = tmpl();  r = S.E.crossing_scaled.res;  w = S.E.walking_scaled.res;  P = S.P;  CA = S.CA;
[~, tl] = newFig(1400, 1000, 2, 2);
ax = tile(tl);
v = 100 * [mean(r(:,2)) mean(r(:,3)) mean(r(:,5)); mean(w(:,2)) mean(w(:,3)) mean(w(:,5))]';
b = vbars(ax, v, [ST.person; ST.generic]);
for i = 1:2
    xt = b(i).XEndPoints;
    for j = 1:3, valText(ax, xt(j), v(j,i) + 1.5, sprintf('%.0f', v(j,i)), 'HorizontalAlignment', 'center', 'VerticalAlignment', 'bottom'); end
end
set(ax, 'XTick', 1:3, 'XTickLabel', {'found', '+ lead / trail', '+ height'});  ylim(ax, [0 112]);
lbl(ax, '', '% of the crossings');
ttl(ax, 'Detect, pair, recognise');
lg = leg(ax, b, {'scaled to own crossings (person)', 'scaled to own walking (generic)'}, 'Orientation', 'horizontal');
lg.Layout.Tile = 'north';
ax = tile(tl);
h = [plot(ax, CA(:,1), 100 * CA(:,3), '-o', 'Color', ST.person, 'LineWidth', ST.lineW, 'MarkerSize', 9, ...
        'MarkerFaceColor', ST.person, 'MarkerEdgeColor', 'w'), ...
     plot(ax, CA(:,1), 100 * CA(:,2), '--s', 'Color', ST.person, 'LineWidth', 2, 'MarkerSize', 9, ...
        'MarkerFaceColor', 'w', 'MarkerEdgeColor', ST.person)];
refLine(ax, 100/3, 'y', 'chance');
set(ax, 'XTick', CA(:,1));  ylim(ax, [20 100]);
lbl(ax, 'earlier crossings used for scaling', '% of the crossings');
ttl(ax, 'Learning during use (causal)');
leg(ax, h, {'all correct', 'height right (found)'}, 'Location', 'northwest');
ax = tile(tl, [1 2]);
a = arrayfun(@(p) 100 * mean(r(r(:,1) == p, 5)), P);
vbars(ax, a(:), ST.person);
for i = 1:numel(P), valText(ax, i, a(i) + 1.5, sprintf('%.0f', a(i)), 'HorizontalAlignment', 'center', 'VerticalAlignment', 'bottom'); end
refLine(ax, 100/3, 'y', 'chance');
set(ax, 'XTick', 1:numel(P), 'XTickLabel', arrayfun(@num2str, P, 'UniformOutput', false));  ylim(ax, [0 112]);
lbl(ax, 'participant (tested unseen)', 'all correct (%)');
ttl(ax, 'Crossings found, paired and classified correctly, per participant');
layoutTitle(tl, 'No camera: the Dot data stream alone (detect, pair, recognise)', ...
    'two foot IMUs, random forest; every participant tested unseen');
saveFig(tl, out, 'fig_stream.png');
end

function figRealworld(out, S)
ST = tmpl();  CUR = S.CUR;  CU = S.CU;  Q = S.Q;  P = S.P;
[~, tl] = newFig(1400, 1000, 2, 2);
ax = tile(tl);
sm = @(v) movmean(v, 3);  nx = numel(CUR.mixed_5);
h = [plot(ax, 1:nx, 100 * sm(CUR.mixed_5), '-', 'Color', ST.person, 'LineWidth', ST.lineW), ...
     plot(ax, 1:nx, 100 * sm(CUR.blocked_5), '-', 'Color', ST.generic, 'LineWidth', ST.lineW)];
evLine(ax, 5.5, 'person scaling', ':');
refLine(ax, 100/3, 'y', '');
ylim(ax, [20 100]);  xlim(ax, [1 nx]);
lbl(ax, 'crossing number in the session', 'accuracy (%, 3-crossing mean)');
ttl(ax, 'The device learns the person');
leg(ax, h, {'mixed obstacle order', 'blocked order (study)'}, 'Location', 'southeast');
ax = tile(tl);
c = polyfit(Q(:,2), 100 * Q(:,5), 1);  xx = [min(Q(:,2)) max(Q(:,2))];
plot(ax, xx, polyval(c, xx), '--', 'Color', ST.ref, 'LineWidth', ST.refW);
scatter(ax, Q(:,2), 100 * Q(:,5), 130, ST.person, 'filled', 'MarkerEdgeColor', ST.edge, 'LineWidth', 1);
xlim(ax, [min(Q(:,2)) - 0.3, max(Q(:,2)) + 0.5]);  ylim(ax, [5 * floor(min(100 * Q(:,5)) / 5) - 3, 103]);
labelPoints(ax, Q(:,2), 100 * Q(:,5), arrayfun(@num2str, P, 'UniformOutput', false));
lbl(ax, 'trailing-foot lift consistency (d'')', 'accuracy, tested unseen (%)');
ttl(ax, sprintf('Consistency sets the accuracy (r = %.2f)', corr(Q(:,2), Q(:,5))));
ax = tile(tl, [1 2]);
sel = find(CU(:,2) == 1);  M = 100 * CU(sel, 4:6);
lab = cell(numel(sel), 1);
for i = 1:numel(sel)
    wh = regexprep(S.cues{CU(sel(i),1),1}, '^lead ', 'leading ');
    if CU(sel(i),3) > 0, th = sprintf('p \\geq %.1f', CU(sel(i),3)); else, th = 'always'; end
    lab{i} = sprintf('%s\\newline%s', wh, th);
end
b = bar(ax, M, 0.62, 'stacked', 'EdgeColor', ST.edge, 'LineWidth', ST.barEdgeW);
b(1).FaceColor = ST.both;  b(2).FaceColor = ST.level;  b(3).FaceColor = ST.raw;
for i = 1:size(M, 1)
    text(ax, i, M(i,1) / 2, sprintf('%.0f', M(i,1)), 'HorizontalAlignment', 'center', 'FontName', ST.font, ...
        'FontSize', ST.szText, 'FontWeight', 'bold', 'Color', 'w');
    if M(i,2) >= 6
        text(ax, i, M(i,1) + M(i,2) / 2, sprintf('%.0f', M(i,2)), 'HorizontalAlignment', 'center', 'FontName', ST.font, ...
            'FontSize', ST.szText, 'FontWeight', 'bold', 'Color', 'w');
    end
end
set(ax, 'XTick', 1:numel(lab), 'XTickLabel', lab, 'TickLabelInterpreter', 'tex');  ylim(ax, [0 100]);  xlim(ax, [0.4 numel(lab) + 0.6]);
lbl(ax, '', '% of the crossings');
ttl(ax, 'Real-time cue to the trailing leg (mixed obstacle order)');
leg(ax, b, {'correct cue', 'wrong cue', 'no cue'}, 'Location', 'eastoutside');
layoutTitle(tl, 'How would the device behave in a real session?', ...
    'two foot IMUs, person scaling learned while walking; every participant tested unseen');
saveFig(tl, out, 'fig_realworld.png');
end

function figLateral(out, S)
ST = tmpl();
[vs, o] = sort(S.ewS(:), 'descend', 'MissingPlacement', 'last');  [vl, ol] = sort(S.ew(:), 'descend', 'MissingPlacement', 'last');
n = 15;
[~, tl] = newFig(1300, 620, 1, 1);
ax = tile(tl);
b = vbars(ax, [vs(1:n), vl(1:n)], [ST.generic; ST.teal]);
ylim(ax, [0 max(0.15, max([vs(1) vl(1)]) * 1.25)]);  set(ax, 'XTick', 1:n);  xlim(ax, [0.4 n + 0.6]);
lbl(ax, 'rank of the feature (most width-sensitive first)', '\eta^2 of width (within person \times height)');
lg = leg(ax, b, {'original sagittal Dot features', 'new out-of-plane features'}, 'Orientation', 'horizontal');
lg.Layout.Tile = 'north';
layoutTitle(tl, 'Width leaves little trace in any axis', sprintf('largest: sagittal %s (%.2f); out-of-plane %s (%.2f)', ...
    strrep(S.F{o(1)}, '_', '\_'), vs(1), strrep(S.names{ol(1)}, '_', '\_'), vl(1)));
saveFig(tl, out, 'fig_lateral.png');
end

%% ========================================================================
%  crossing_ml_validate, crossing_ml_haptic
%% ========================================================================
function figValidate(out, S)
ST = tmpl();  R1 = S.R1;  R3 = S.R3;  R4 = S.R4;  R5 = S.R5;
[~, tl] = newFig(1600, 1020, 2, 2);
% V1
ax = tile(tl);
lab = {'H1', 'H2', 'H3'};  V = zeros(3, 4);  y = R1.y;  h = R1.h;
src = {R1.self.ridge.ref, R1.self.forest.ref, R1.self.ridge.loho, R1.self.forest.loho};
for c = 1:3, m = strcmp(y, lab{c});  for s = 1:4, V(c, s) = mean(abs(src{s}(m) - h(m))); end, end
b = vbars(ax, V, [0.82 0.82 0.82; 0.50 0.50 0.50; ST.both + 0.5 * (1 - ST.both); ST.both]);
set(ax, 'XTick', 1:3, 'XTickLabel', {'H1 (lowest)', 'H2 (middle)', 'H3 (highest)'});  ylim(ax, [0 max(V(:)) * 1.65]);
lbl(ax, '', 'mean absolute error (cm)');
ttl(ax, 'V1  A height level never trained');
lg = leg(ax, b, {'ridge, all heights trained', 'forest, all heights trained', 'ridge, height left out', 'forest, height left out'}, ...
    'Location', 'northwest');
lg.FontSize = 12;
% V3
ax = tile(tl);
nm = {'camera toe peak', 'camera take-off distance', 'camera peak + take-off', 'IMU foot lift', 'IMU toe rise', 'IMU lift + camera take-off'};
n = numel(nm);
bh = barh(ax, (n:-1:1)', 100 * [R3.lead(:), R3.trail(:)], 'grouped', 'BarWidth', 0.85, 'EdgeColor', ST.edge, 'LineWidth', ST.barEdgeW);
bh(1).FaceColor = ST.lead;  bh(2).FaceColor = ST.trail;
set(ax, 'YTick', 1:n, 'YTickLabel', flip(nm));  xlim(ax, [0 100]);  ylim(ax, [0.4 n + 0.6]);
lbl(ax, 'clearance variance explained (%)', '');
ttl(ax, 'V3  What sets the toe clearance?');
leg(ax, bh, {'leading limb', 'trailing limb'}, 'Location', 'southeast');
% V4
ax = tile(tl);
[v, o] = sort(R4.drop(:), 'ascend');  n = numel(v);  nm = R4.names(o);  nm = nm(:);      % drop = base - shuffled
cc = repmat(ST.trail, n, 1);  isL = startsWith(nm, 'lead');  cc(isL, :) = repmat(ST.lead, nnz(isL), 1);
hbars(ax, (1:n)', v, cc);
errorbar(ax, v, (1:n)', R4.sd(o), 'horizontal', 'LineStyle', 'none', 'Color', ST.ink, 'LineWidth', ST.errW, 'CapSize', 4);
xline(ax, 0, '-', 'Color', ST.ink, 'LineWidth', 1.2, 'HandleVisibility', 'off');
nm = regexprep(regexprep(nm, '^lead(:)? ?', 'leading '), '^trail(:)? ?', 'trailing ');
set(ax, 'YTick', 1:n, 'YTickLabel', nm);  ylim(ax, [0.4 n + 0.6]);
lbl(ax, 'accuracy lost when shuffled (points)', '');
ttl(ax, sprintf('V4  What the device model uses (%.0f%%)', 100 * R4.base));
leg(ax, [keyPatch(ax, ST.lead), keyPatch(ax, ST.trail)], {'leading foot', 'trailing foot'}, 'Location', 'southeast');
% V5
ax = tile(tl);
hp = plot(ax, [0.25 1], [0.25 1], '--', 'Color', ST.ref, 'LineWidth', ST.refW);
tabs = {R5.tG, ST.generic; R5.tF, ST.person};  hh = gobjects(2, 1);
for t = 1:2
    tb = tabs{t,1};  m = tb(:,3) >= 5;
    hh(t) = plot(ax, tb(m,4), tb(m,5), '-o', 'Color', tabs{t,2}, 'LineWidth', ST.lineW, 'MarkerSize', 9, ...
        'MarkerFaceColor', tabs{t,2}, 'MarkerEdgeColor', 'w');
end
xlim(ax, [0.25 1]);  ylim(ax, [0.25 1]);  axis(ax, 'square');
lbl(ax, 'stated probability', 'observed accuracy');
ttl(ax, 'V5  Are the probabilities trustworthy?');
leg(ax, [hp; hh], {'perfect calibration', 'generic model', 'person scaling'}, 'Location', 'eastoutside');
layoutTitle(tl, 'Generalisation and validation of the obstacle-height model', ...
    'two foot IMUs, random forest per limb; every participant tested unseen; V5 bins with \geq 5 crossings');
saveFig(tl, out, 'fig_validate.png');
end

function figHaptic(out, S)
ST = tmpl();  R5 = S.R5;  tA = S.tA(:)';
sig = {'thigh', 'thigh tilt'; 'shank', 'shank tilt'; 'foot', 'foot tilt'; 'zhc_h', 'foot height'};
[~, tl] = newFig(1500, 680, 1, 2);
lim = {'lead', 'Leading limb'; 'trail', 'Trailing limb'};  hs = gobjects(4, 1);
for li = 1:2
    ax = tile(tl);
    patch(ax, [-300 0 0 -300], [20 20 100 100], [0.90 0.90 0.90], 'EdgeColor', 'none', 'HandleVisibility', 'off');
    for s = 1:4
        hs(s) = plot(ax, tA, 100 * R5.(lim{li,1}).(sig{s,1}).cen, '-', 'Color', ST.seg(s,:), 'LineWidth', ST.lineW);
    end
    evLine(ax, 0, 'trailing toe lift-off');
    evLine(ax, S.tImu, 'step-4 toe-off (IMU)', ':');
    refLine(ax, 100/3, 'y', '');
    ylim(ax, [20 100]);  xlim(ax, [tA(1) tA(end)]);
    lbl(ax, 'time to trailing toe lift-off (ms)', 'height accuracy (%)');
    ttl(ax, lim{li,2});
end
lg = leg(ax, hs, sig(:,2)', 'Orientation', 'horizontal');  lg.Layout.Tile = 'north';
layoutTitle(tl, 'Haptic cue: when does one signal tell the obstacle height?', ...
    ['person-centred thresholds learned on 9 participants, tested on the 10th; time 0 = trailing toe lift-off (camera); ' ...
     'grey = last 300 ms; dashed = chance']);
saveFig(tl, out, 'fig_haptic.png');
end

function figHapticCurves(out, S)
ST = tmpl();  W = S.W;  tA = S.tA(:)';  yo = S.yo;  go = S.go;  P = S.P(:)';
[~, tl] = newFig(1400, 1000, 2, 2);
pn = {'lead', 'thigh', 'Leading thigh tilt', 'change vs normal walking (deg)', 'northeast';
      'trail', 'shank', 'Trailing shank tilt', 'change vs normal walking (deg)', 'southwest';
      'lead', 'zhc_h', 'Leading foot height', 'change vs normal walking (mm)', 'northeast';
      'trail', 'zhc_h', 'Trailing foot height', 'change vs normal walking (mm)', 'northwest'};
for q = 1:4
    ax = tile(tl);
    A = W.(pn{q,1}).(pn{q,2}).ref;
    if strcmp(pn{q,1}, 'lead'), hc = ramp3(ST.lead); else, hc = ramp3(ST.trail); end
    hh = gobjects(3, 1);
    for c = 1:3
        pm = cell2mat(arrayfun(@(p) mean(A(go == p & yo == c, :), 1, 'omitnan'), P(:), 'UniformOutput', false));
        hh(c) = plot(ax, tA, mean(pm, 1, 'omitnan'), '-', 'Color', hc(c,:), 'LineWidth', ST.lineW);
    end
    yline(ax, 0, ':', 'Color', ST.ref, 'LineWidth', 1.4, 'HandleVisibility', 'off');
    evLine(ax, 0, '');
    xlim(ax, [tA(1) tA(end)]);
    lbl(ax, 'time to trailing toe lift-off (ms)', pn{q,4});
    ttl(ax, pn{q,3});
    leg(ax, hh, {'H1', 'H2', 'H3'}, 'Location', pn{q,5});
end
layoutTitle(tl, 'The candidate cue signals around the trailing toe lift-off', ...
    ['mean of the 10 participant means, relative to the person''s normal walking; H1 / H2 / H3 = 10 / 20 / 30% of leg length; ' ...
     'time 0 = trailing toe lift-off (camera)']);
saveFig(tl, out, 'fig_haptic_curves.png');
end

%% ========================================================================
%  crossing_ml_story: map, person, strategy, embed
%% ========================================================================
function figStoryMap(out, S)
ST = tmpl();  E = S.E;
top = max([E.lead.height(:); E.trail.height(:)]);
[~, tl] = newFig(1500, 980, 2, 2);
lim = {'lead', 'Leading', S.apex, ST.lead; 'trail', 'Trailing', S.apexT, ST.trail};
for li = 1:2
    for tg = {'height', 'width'}
        ax = tile(tl);
        imagesc(ax, 0:2:100, 1:numel(S.sigName), E.(lim{li,1}).(tg{1}), [0 top]);  colormap(ax, seqMap(lim{li,4}));
        axis(ax, 'tight');  set(ax, 'YDir', 'reverse');
        evLine(ax, lim{li,3}, '', '--');
        set(ax, 'YTick', 1:numel(S.sigName), 'YTickLabel', S.sigName, 'TickLength', [0.005 0.005]);
        lbl(ax, '% of swing (toe-off to heel strike)', '');
        ttl(ax, sprintf('%s limb: obstacle %s', lim{li,2}, tg{1}));
        cb = colorbar(ax);  cb.Label.String = '\eta^2 (within person)';
        set(cb, 'FontName', ST.font, 'FontSize', ST.szTick, 'FontWeight', 'bold', 'LineWidth', 1.2, 'Color', ST.ink);
        set(cb.Label, 'FontSize', 14, 'FontWeight', 'bold');
    end
end
layoutTitle(tl, 'Where in the swing is the obstacle encoded?', ...
    ['share of the within-person variance explained by obstacle height or width at each moment of the swing (\eta^2); ' ...
     'dashed = median foot apex']);
saveFig(tl, out, 'fig_story_map.png');
end

function figStoryPerson(out, S)
ST = tmpl();
v = {S.ep, S.eh, S.ehw};  cols = [ST.person; ST.generic; ST.both];
[~, tl] = newFig(1150, 680, 1, 1);
ax = tile(tl);
for k = 1:3
    x = v{k}(:);  x = x(isfinite(x));
    boxchart(ax, k * ones(numel(x), 1), x, 'BoxFaceColor', cols(k,:), 'BoxFaceAlpha', 0.6, 'BoxWidth', 0.5, ...
        'LineWidth', 1.6, 'WhiskerLineColor', ST.ink, 'MarkerColor', ST.ink, 'MarkerStyle', 'o', 'MarkerSize', 6);
end
set(ax, 'XTick', 1:3, 'XTickLabel', {'participant (who)', 'obstacle height', 'height within person'});
ylim(ax, [0 1]);  xlim(ax, [0.4 3.6]);
lbl(ax, '', 'variance explained per feature (\eta^2)');
layoutTitle(tl, sprintf('The walking signature dominates: one crossing identifies the person (%.0f%%)', 100 * S.idAcc), ...
    'each box = all Dot features (median, quartiles, whiskers to 1.5 IQR); identification chance = 10%');
saveFig(tl, out, 'fig_story_person.png');
end

function figStoryStrategy(out, S)
ST = tmpl();  x = S.x;  g = S.g;  P = unique(g)';
nm = {'Leading foot lift', 'Trailing foot lift'};  base = [ST.lead; ST.trail];
[~, tl] = newFig(1400, 1000, 2, 2);
for v = 1:2
    ax = tile(tl);
    yv = S.Y(:, v);
    for k = 1:numel(P)
        m = g == P(k) & isfinite(yv) & isfinite(x);
        scatter(ax, x(m), yv(m), 26, base(v,:), 'filled', 'MarkerFaceAlpha', 0.25);
        c = polyfit(x(m), yv(m), 1);  xx = [min(x(m)) max(x(m))];
        plot(ax, xx, polyval(c, xx), '-', 'Color', base(v,:), 'LineWidth', 1.8);
    end
    lbl(ax, 'obstacle height (cm)', 'peak foot height (mm)');
    ttl(ax, sprintf('%s: %.1f mm per cm', nm{v}, median(S.SL(:, v), 'omitnan')));
end
ax = tile(tl);
for v = 1:2
    s = S.SL(:, v);  s = s(isfinite(s));  jit = ((1:numel(s))' - (numel(s) + 1) / 2) * 0.03;
    scatter(ax, v + jit, s, 110, base(v,:), 'filled', 'MarkerEdgeColor', ST.edge, 'LineWidth', 1);
    plot(ax, v + [-0.28 0.28], median(s) * [1 1], '-', 'Color', ST.ink, 'LineWidth', 3);
end
yline(ax, 10, '--', 'one-to-one', 'Color', ST.ref, 'LineWidth', ST.refW, 'FontName', ST.font, 'FontSize', ST.szText, ...
    'FontWeight', 'bold', 'LabelHorizontalAlignment', 'right', 'LabelVerticalAlignment', 'bottom', 'HandleVisibility', 'off');
sl = S.SL(:, 1:2);  sl = sl(isfinite(sl));
set(ax, 'XTick', 1:2, 'XTickLabel', {'leading foot', 'trailing foot'});  xlim(ax, [0.4 2.6]);
ylim(ax, [floor(min([sl; 10])) - 1, ceil(max([sl; 10])) + 1]);
lbl(ax, '', 'slope (mm per cm of obstacle)');
ttl(ax, 'One slope per participant');
ax = tile(tl);
h = gobjects(2, 1);
for v = 1:2
    fill(ax, [1:5 5:-1:1], [S.ADlo(v,:) fliplr(S.ADhi(v,:))], base(v,:), 'FaceAlpha', 0.15, 'EdgeColor', 'none');
    h(v) = plot(ax, 1:5, S.AD(v,:), '-o', 'Color', base(v,:), 'LineWidth', ST.lineW, 'MarkerSize', 9, ...
        'MarkerFaceColor', base(v,:), 'MarkerEdgeColor', 'w');
end
yline(ax, 0, '-', 'Color', ST.ref, 'LineWidth', 1.4, 'HandleVisibility', 'off');
set(ax, 'XTick', 1:5);  xlim(ax, [0.8 5.2]);
lbl(ax, 'repeat of the same obstacle', 'vs own mean for the obstacle (mm)');
ttl(ax, 'Foot lift over the 5 repeats');
leg(ax, h, {'leading foot', 'trailing foot'}, 'Location', 'northeast');
layoutTitle(tl, 'Crossing strategy: each foot is lifted by about the obstacle height', ...
    'Dot foot sensor; points = crossings, lines = one fit per participant; band = 95% participant-bootstrap CI');
saveFig(tl, out, 'fig_story_strategy.png');
end

function figStoryEmbed(out, S)
ST = tmpl();  g = S.g;  P = unique(g)';
pc = [31 119 180; 255 127 14; 44 160 44; 214 39 40; 148 103 189; 140 86 75; 227 119 194; 127 127 127; 188 189 34; 23 190 207] / 255;
[~, tl] = newFig(1400, 720, 1, 2);
ax = tile(tl);
h = gobjects(numel(P), 1);
for k = 1:numel(P)
    m = g == P(k);
    h(k) = scatter(ax, S.Yr(m,1), S.Yr(m,2), 34, pc(k,:), 'filled', 'MarkerFaceAlpha', 0.8);
end
set(ax, 'XTick', [], 'YTick', []);  axis(ax, 'square');
ttl(ax, sprintf('Raw: by participant (silhouette %.2f)', S.sil(1)));
lg = leg(ax, h, arrayfun(@num2str, P, 'UniformOutput', false), 'Location', 'eastoutside');  lg.FontSize = 12;
ax = tile(tl);
hc = ramp3(ST.person);  hl = {'H1', 'H2', 'H3'};  h3 = gobjects(3, 1);
for k = 1:3
    m = strcmp(S.y, hl{k});
    h3(k) = scatter(ax, S.Ys(m,1), S.Ys(m,2), 34, hc(k,:), 'filled', 'MarkerFaceAlpha', 0.85);
end
set(ax, 'XTick', [], 'YTick', []);  axis(ax, 'square');
ttl(ax, sprintf('Person-scaled: by height (silhouette %.2f)', S.sil(4)));
leg(ax, h3, hl, 'Location', 'eastoutside');
layoutTitle(tl, 'A map of all crossings (t-SNE of the Dot features)', ...
    'raw features cluster by person; after person scaling the crossings order by obstacle height');
saveFig(tl, out, 'fig_story_embed.png');
end

%% ========================================================================
%  crossing_ml_stats, crossing_ml_robust
%% ========================================================================
function figStats(out, S)
ST = tmpl();  A = S.S1;  nV = numel(A);
[~, tl] = newFig(1600, 1040, 2, 2);
% partial eta^2 of the repeated-measures ANOVA
ax = tile(tl);
E = reshape([A.eta], 3, [])';  Pv = reshape([A.p], 3, [])';
imagesc(ax, E, [0 1]);  colormap(ax, seqMap(ST.teal));
for i = 1:nV
    for j = 1:3
        col = ST.ink;  if E(i,j) > 0.55, col = [1 1 1]; end
        text(ax, j, i, sprintf('%.2f%s', E(i,j), stars(Pv(i,j))), 'HorizontalAlignment', 'center', 'FontName', ST.font, ...
            'FontSize', ST.szText, 'FontWeight', 'bold', 'Color', col);
    end
end
nm = strrep(regexprep({A.name}, ' \(Dot\)', ''), 'minimum clearance (camera)', 'clearance (camera)');
lb = strrep(strrep({A.limb}, 'lead', 'leading'), 'trail', 'trailing');
set(ax, 'YDir', 'reverse', 'XTick', 1:3, 'XTickLabel', {'height', 'width', 'height \times width'}, 'YTick', 1:nV, ...
    'YTickLabel', strcat(lb, {' '}, nm), 'TickLength', [0 0]);
xlim(ax, [0.5 3.5]);  ylim(ax, [0.5 nV + 0.5]);
ttl(ax, 'Partial \eta^2 (repeated-measures ANOVA)');
% step 9-style bars: Dot foot lift per obstacle
ax = tile(tl);
b = vbars(ax, S.lift.mean', [ST.lead; ST.trail]);
for k = 1:2
    errorbar(ax, b(k).XEndPoints, S.lift.mean(k,:), S.lift.sd(k,:), 'LineStyle', 'none', 'Color', ST.ink, 'LineWidth', ST.errW, ...
        'CapSize', 4, 'HandleVisibility', 'off');
end
set(ax, 'XTick', 1:6, 'XTickLabel', strrep(S.lift.cells, '_', '\_'));  xtickangle(ax, 20);
lbl(ax, '', 'foot lift (mm)');
ttl(ax, 'Dot foot lift per obstacle (mean \pm SD)');
leg(ax, b, {'leading limb', 'trailing limb'}, 'Location', 'northwest');
% Bland-Altman: Dot foot lift vs camera toe rise
ax = tile(tl);
lim = {'lead', ST.lead; 'trail', ST.trail};  h = gobjects(2, 1);
for k = 1:2
    B = S.BA.(lim{k,1});
    h(k) = scatter(ax, B.mean, B.diff, 24, lim{k,2}, 'filled', 'MarkerFaceAlpha', 0.35);
    yline(ax, B.bias, '-', 'Color', lim{k,2}, 'LineWidth', 2.4, 'HandleVisibility', 'off');
    yline(ax, B.lo, '--', 'Color', lim{k,2}, 'LineWidth', 1.8, 'HandleVisibility', 'off');
    yline(ax, B.hi, '--', 'Color', lim{k,2}, 'LineWidth', 1.8, 'HandleVisibility', 'off');
end
hk = [plot(ax, NaN, NaN, '-', 'Color', ST.ink, 'LineWidth', 2.4), plot(ax, NaN, NaN, '--', 'Color', ST.ink, 'LineWidth', 1.8)];
lbl(ax, 'mean of Dot and camera (mm)', 'Dot - camera (mm)');
ttl(ax, 'Foot lift: Dot sensor vs camera toe (Bland-Altman)');
leg(ax, [h; hk(:)], {'leading', 'trailing', 'bias', '95% limits of agreement'}, 'Location', 'southwest', 'NumColumns', 2);
% paired model comparisons
ax = tile(tl);
M = S.MC;  n = numel(M.d);  yy = (n:-1:1)';  sig = M.pM(:) < 0.05;
cc = repmat(ST.generic, n, 1);  cc(sig, :) = repmat(ST.person, nnz(sig), 1);
hbars(ax, yy, M.d(:), cc);
errorbar(ax, M.d(:), yy, M.d(:) - M.lo(:), M.hi(:) - M.d(:), 'horizontal', 'LineStyle', 'none', 'Color', ST.ink, ...
    'LineWidth', ST.errW, 'CapSize', 4);
xline(ax, 0, '-', 'Color', ST.ink, 'LineWidth', 1.2, 'HandleVisibility', 'off');
for i = 1:n
    if M.pM(i) < 0.001, s = 'p < 0.001'; else, s = sprintf('p = %.3f', M.pM(i)); end
    valText(ax, max(M.hi(i), M.d(i)) + 1, yy(i), s, 'VerticalAlignment', 'middle');
end
set(ax, 'YTick', 1:n, 'YTickLabel', flip(M.short));  ylim(ax, [0.4 n + 0.6]);
xlim(ax, [min([M.lo(:); 0]) - 3, max(M.hi(:)) + 16]);
lbl(ax, 'difference in balanced accuracy (points)', '');
ttl(ax, 'Paired model comparisons (McNemar, Holm)');
leg(ax, [keyPatch(ax, ST.person), keyPatch(ax, ST.generic)], {'significant', 'not significant'}, 'Location', 'southeast');
layoutTitle(tl, 'Statistics of the crossing variables and of the model comparisons', ...
    ['limbs analysed separately; ***, **, * = p < 0.001, 0.01, 0.05 (Greenhouse-Geisser); bars: mean \pm SD of the 10 participant ' ...
     'means; model comparisons: 95% participant-bootstrap CI']);
saveFig(tl, out, 'fig_stats.png');
end

function figRobust(out, S)
ST = tmpl();  cc = [ST.lead; ST.both];  mk = {'o', 's'};
[~, tl] = newFig(1500, 1040, 2, 2);
% sampling rate
ax = tile(tl);  r = S.rate;  h = gobjects(2, 1);
for k = 1:2
    fill(ax, [r.hz fliplr(r.hz)], 100 * [r.lo(k,:) fliplr(r.hi(k,:))], cc(k,:), 'FaceAlpha', 0.15, 'EdgeColor', 'none');
    h(k) = plot(ax, r.hz, 100 * r.b(k,:), ['-' mk{k}], 'Color', cc(k,:), 'LineWidth', ST.lineW, 'MarkerSize', 9, ...
        'MarkerFaceColor', cc(k,:), 'MarkerEdgeColor', 'w');
end
refLine(ax, 100/3, 'y', '');
set(ax, 'XDir', 'reverse', 'XTick', sort(r.hz));  xlim(ax, [8 62]);  ylim(ax, [20 100]);
lbl(ax, 'sampling rate (Hz)', 'balanced accuracy (%)');
ttl(ax, 'Sampling rate');
lg = leg(ax, h, {'real-time cue: leading limb, 0.3 s before lift-off', 'after the crossing: both limbs'}, 'Orientation', 'horizontal');
lg.Layout.Tile = 'north';
% noise
ax = tile(tl);  z = S.noise;  x = 0:size(z.b, 2) - 1;
for k = 1:2
    errorbar(ax, x, 100 * z.b(k,:), 100 * (z.b(k,:) - z.lo(k,:)), 100 * (z.hi(k,:) - z.b(k,:)), ['-' mk{k}], 'Color', cc(k,:), ...
        'LineWidth', ST.lineW, 'MarkerSize', 9, 'MarkerFaceColor', cc(k,:), 'MarkerEdgeColor', 'w', 'CapSize', 5);
end
refLine(ax, 100/3, 'y', '');
set(ax, 'XTick', x, 'XTickLabel', [{'none'}, arrayfun(@(a, b) sprintf('%d%c / %d mm', a, 176, b), [1 2 4 8], [5 10 20 40], ...
    'UniformOutput', false)]);
xlim(ax, [-0.3 x(end) + 0.3]);  ylim(ax, [20 100]);
lbl(ax, 'added noise (tilt / foot height)', 'balanced accuracy (%)');
ttl(ax, 'Sensor noise');
% model size
ax = tile(tl);  z = S.size;  pc = [ST.person + 0.45 * (1 - ST.person); ST.person; 0.55 * ST.person];  fm = {'o', 's', 'd'};
hs = gobjects(numel(z.leaf) + 1, 1);  nmz = cell(numel(z.leaf) + 1, 1);
for i = 1:numel(z.leaf)
    hs(i) = plot(ax, z.fbytes(i,:) / 1024, 100 * z.fb(i,:), ['-' fm{i}], 'Color', pc(i,:), 'LineWidth', 2, 'MarkerSize', 8, ...
        'MarkerFaceColor', pc(i,:), 'MarkerEdgeColor', 'w');
    nmz{i} = sprintf('forest, minimum leaf %d', z.leaf(i));
end
hs(end) = plot(ax, z.lbytes / 1024, 100 * z.lb, '-^', 'Color', ST.both, 'LineWidth', 2, 'MarkerSize', 9, 'MarkerFaceColor', ST.both, ...
    'MarkerEdgeColor', 'w');
nmz{end} = 'logistic, k features';
set(ax, 'XScale', 'log');  ylim(ax, [60 100]);
lbl(ax, 'model memory (kB, log scale)', 'balanced accuracy (%)');
ttl(ax, 'Model size');
leg(ax, hs, nmz, 'Location', 'southeast');
% conformal prediction sets
ax = tile(tl);  z = S.conf;
Mx = 100 * [z.singleRight; z.single - z.singleRight; z.adjacent; z.nonadj + z.all3; z.empty]';
b = bar(ax, Mx, 0.6, 'stacked', 'EdgeColor', ST.edge, 'LineWidth', ST.barEdgeW);
fc = [ST.both; ST.level; ST.teal + 0.5 * (1 - ST.teal); ST.generic; ST.raw];
for k = 1:numel(b), b(k).FaceColor = fc(k,:); end
for a = 1:numel(z.alpha)
    valText(ax, a, 103, sprintf('covered %.0f%%', 100 * z.cover(a)), 'HorizontalAlignment', 'center', 'VerticalAlignment', 'bottom');
end
set(ax, 'XTick', 1:numel(z.alpha), 'XTickLabel', arrayfun(@(a) sprintf('%.0f%%', 100 * (1 - a)), z.alpha, 'UniformOutput', false));
ylim(ax, [0 115]);  xlim(ax, [0.4 numel(z.alpha) + 0.6]);
lbl(ax, 'target coverage', '% of the crossings');
ttl(ax, 'Prediction sets (conformal)');
leg(ax, b, {'one height, right', 'one height, wrong', 'two neighbouring', 'H1 + H3 or all three', 'empty'}, 'Location', 'eastoutside');
layoutTitle(tl, 'Device robustness: sampling rate, sensor noise, model size and prediction sets', ...
    'obstacle height (3 classes, chance 33%), person scaling, random forest unless stated; every participant tested unseen');
saveFig(tl, out, 'fig_robust.png');
end

function figParams(out, S)
% Significance map of the 26 step 9 parameters (crossing_ml_params.m): partial eta^2 with FDR stars, and the
% obstacle-vs-level-walk effect size on the same rows.
ST = tmpl();  cls = unique(S.class, 'stable');  nV = numel(S.names);  nR = 1 + numel(cls) + nV;
hd = struct('clearance', 'CLEARANCE (camera)', 'joint', 'JOINT ANGLES (IK)', 'segment', 'SEGMENT TILTS (Dot)', ...
    'timing', 'PEAK TIMING (vs clearance)', 'spatiotemporal', 'SPATIOTEMPORAL');
lab = repmat({''}, nR, 1);  rowOf = zeros(nV, 1);  hdr = zeros(numel(cls), 1);  r = 1;
for c = 1:numel(cls)
    r = r + 1;  hdr(c) = r;  lab{r} = sprintf('\\color[rgb]{%.2f %.2f %.2f}%s', ST.sub, hd.(cls{c}));
    for v = find(strcmp(S.class, cls{c}))
        r = r + 1;  rowOf(v) = r;  lab{r} = S.names{v};
    end
end
[~, tl] = newFig(1500, 1040, 1, 3);
% partial eta^2 (rows = parameters, columns = leading height / width / interaction, then trailing)
ax = tile(tl, [1 2]);
E = nan(nR, 6);  Q = nan(nR, 6);  G = false(nR, 6);  E(rowOf, :) = S.eta;  Q(rowOf, :) = S.q;
G(rowOf, :) = [repmat(S.flag(:, 1), 1, 3), repmat(S.flag(:, 2), 1, 3)];       % verdict depends on outlying cells
im = imagesc(ax, E, [0 1]);  im.AlphaData = double(isfinite(E));  colormap(ax, seqMap(ST.teal));
for i = 1:nR
    for j = 1:6
        if ~isfinite(E(i,j)), continue; end
        col = ST.ink;  if E(i,j) > 0.55, col = [1 1 1]; end
        dg = '';  if G(i,j), dg = char(8224); end
        text(ax, j, i, sprintf('%.2f%s%s', E(i,j), stars(Q(i,j)), dg), 'HorizontalAlignment', 'center', 'FontName', ST.font, ...
            'FontSize', ST.szText, 'FontWeight', 'bold', 'Color', col);
    end
end
xline(ax, 3.5, '-', 'Color', 'w', 'LineWidth', 6, 'HandleVisibility', 'off');
text(ax, 2, 1, 'leading limb', 'HorizontalAlignment', 'center', 'FontName', ST.font, 'FontSize', ST.szLabel, 'FontWeight', 'bold', 'Color', ST.lead);
text(ax, 5, 1, 'trailing limb', 'HorizontalAlignment', 'center', 'FontName', ST.font, 'FontSize', ST.szLabel, 'FontWeight', 'bold', 'Color', ST.trail);
set(ax, 'YDir', 'reverse', 'XTick', 1:6, 'XTickLabel', repmat({'height', 'width', 'H \times W'}, 1, 2), 'YTick', 1:nR, ...
    'YTickLabel', lab, 'TickLength', [0 0]);
xlim(ax, [0.5 6.5]);  ylim(ax, [0.5 nR + 0.5]);
ttl(ax, 'Partial \eta^2 of the repeated-measures ANOVA (stars: FDR q)');
% obstacle (mean of the six) minus level walk, d_z
ax = tile(tl);
xline(ax, 0, '-', 'Color', ST.ink, 'LineWidth', 1.2, 'HandleVisibility', 'off');
for c = 1:numel(cls), yline(ax, hdr(c), '-', 'Color', [0.85 0.85 0.85], 'LineWidth', 1, 'HandleVisibility', 'off'); end
col = [ST.lead; ST.trail];  mk = {'o', 's'};  off = [-0.17 0.17];
for l = 1:2
    y = rowOf + off(l);  x = S.dz(:, l);  sg = S.qLev(:, l) < 0.05;  ns = isfinite(x) & ~sg;
    plot(ax, x(sg), y(sg), mk{l}, 'MarkerSize', 9, 'MarkerFaceColor', col(l,:), 'MarkerEdgeColor', col(l,:), 'LineWidth', 1.5);
    plot(ax, x(ns), y(ns), mk{l}, 'MarkerSize', 9, 'MarkerFaceColor', 'w', 'MarkerEdgeColor', col(l,:), 'LineWidth', 1.5);
end
xr = [min([S.dz(:); 0]), max([S.dz(:); 0])];  pad = 0.08 * diff(xr);
set(ax, 'YDir', 'reverse', 'YTick', []);  ylim(ax, [0.5 nR + 0.5]);  xlim(ax, xr + [-pad pad]);
ic = find(strcmp(cls, 'clearance'));
if ~isempty(ic), valText(ax, 0.04 * diff(xlim(ax)), hdr(ic) + 3, 'no level-walk value', 'HorizontalAlignment', 'left'); end
lbl(ax, 'obstacles - level walk (d_z)', '');
ttl(ax, 'Obstacle vs level walk');
k = [plot(ax, NaN, NaN, 'o', 'MarkerSize', 9, 'MarkerFaceColor', ST.lead, 'MarkerEdgeColor', ST.lead, 'LineWidth', 1.5), ...
     plot(ax, NaN, NaN, 's', 'MarkerSize', 9, 'MarkerFaceColor', ST.trail, 'MarkerEdgeColor', ST.trail, 'LineWidth', 1.5), ...
     plot(ax, NaN, NaN, 'o', 'MarkerSize', 9, 'MarkerFaceColor', 'w', 'MarkerEdgeColor', ST.ref, 'LineWidth', 1.5)];
lg = leg(ax, k, {'leading, q < 0.05', 'trailing, q < 0.05', 'open: not significant'}, 'Orientation', 'horizontal');
lg.Layout.Tile = 'south';
layoutTitle(tl, 'Significance of the 26 step 9 parameters', {sprintf(['participant means (n = %d); ***, **, * = q < 0.001, 0.01, 0.05 ' ...
    '(FDR over the 52 tests of each effect)'], S.n), sprintf(['%s = the verdict at p < 0.05 changes without the participants with ' ...
    'outlying cells; right: d_z of the six-obstacle mean minus the level walk'], char(8224))});
saveFig(tl, out, 'fig_params.png');
end

function figParamsClear(out, S)
% Clearance class: change from H1 to H3 and from W1 to W2 with 90 % CI (equivalence view).
ST = tmpl();  E = S.clr;  n = numel(E.names);  yy = (1:n)';  col = [ST.lead; ST.trail];  nm = {'Leading limb', 'Trailing limb'};
[~, tl] = newFig(1500, 640, 1, 2);
xr = [min([E.loH(:); E.loW(:); 0]), max([E.hiH(:); E.hiW(:); 0])];  pad = 0.08 * diff(xr);
for l = 1:2
    ax = tile(tl);
    xline(ax, 0, '-', 'Color', ST.ink, 'LineWidth', 1.2, 'HandleVisibility', 'off');
    errorbar(ax, E.dH(:, l), yy - 0.15, E.dH(:, l) - E.loH(:, l), E.hiH(:, l) - E.dH(:, l), 'horizontal', 'LineStyle', 'none', ...
        'Marker', 'o', 'MarkerSize', 9, 'MarkerFaceColor', col(l,:), 'Color', col(l,:), 'LineWidth', 1.8, 'CapSize', 6);
    errorbar(ax, E.dW(:, l), yy + 0.15, E.dW(:, l) - E.loW(:, l), E.hiW(:, l) - E.dW(:, l), 'horizontal', 'LineStyle', 'none', ...
        'Marker', 's', 'MarkerSize', 9, 'MarkerFaceColor', 'w', 'Color', col(l,:), 'LineWidth', 1.8, 'CapSize', 6);
    set(ax, 'YDir', 'reverse', 'YTick', yy, 'YTickLabel', E.names);  ylim(ax, [0.4 n + 0.6]);  xlim(ax, xr + [-pad pad]);
    if l == 2, set(ax, 'YTickLabel', {}); end
    lbl(ax, 'change (cm), mean with 90% CI', '');
    ttl(ax, nm{l});
end
k = [plot(ax, NaN, NaN, 'o', 'MarkerSize', 9, 'MarkerFaceColor', ST.ink, 'MarkerEdgeColor', ST.ink, 'LineWidth', 1.5), ...
     plot(ax, NaN, NaN, 's', 'MarkerSize', 9, 'MarkerFaceColor', 'w', 'MarkerEdgeColor', ST.ink, 'LineWidth', 1.5)];
lg = leg(ax, k, {'height: H3 - H1', 'width: W2 - W1'}, 'Orientation', 'horizontal');
lg.Layout.Tile = 'south';
layoutTitle(tl, 'Clearance class: change with obstacle height and width', sprintf(['participant means (n = %d) with 90%% CI: a change ' ...
    'beyond the CI is excluded (TOST, \\alpha = 0.05); from H1 to H3 the obstacle rises by %.1f cm'], S.n, E.rise));
saveFig(tl, out, 'fig_params_clear.png');
end

function s = stars(p)
if p < 0.001, s = '***'; elseif p < 0.01, s = '**'; elseif p < 0.05, s = '*'; else, s = ''; end
end

%% ========================================================================
%  TEMPLATE (step 9) AND DRAWING HELPERS
%% ========================================================================
function ST = tmpl()
% Step 9 template values (step09_group_crossing_analysis.m, PLOT STYLE) + colours of the ML figures.
ST.font = 'Arial';
ST.szSgtitle = 18;  ST.szTitle = 16;  ST.szLabel = 16;  ST.szTick = 13;  ST.szLegend = 14;  ST.szSub = 12;
ST.szText = 12;                                   % in-plot labels (step 9: "% vs level" labels 12)
ST.boxWidth = 2.0;  ST.barEdgeW = 0.8;  ST.errW = 1.2;  ST.lineW = 2.4;  ST.refW = 1.8;  ST.pngDPI = 300;
ST.ink = [0.15 0.15 0.15];  ST.edge = [0.20 0.20 0.20];  ST.sub = [0.35 0.35 0.35];  ST.txt = [0.25 0.25 0.25];
ST.lead = [0.20 0.40 0.80];  ST.trail = [0.90 0.50 0.10];  ST.level = [0.85 0.10 0.10];   % step 9 colours
ST.both = [0.20 0.60 0.35];  ST.generic = [0.62 0.62 0.62];  ST.person = [0.50 0.30 0.70];
ST.raw = [0.86 0.86 0.86];  ST.teal = [0.00 0.55 0.55];  ST.ref = [0.40 0.40 0.40];
ST.seg = [0.00 0.55 0.55; 0.75 0.20 0.55; 0.55 0.40 0.15; 0.10 0.10 0.10];   % thigh, shank, foot tilt, foot height
end

function [f, tl] = newFig(w, h, rows, cols)
f = figure('Visible', 'off', 'Color', 'w', 'Units', 'pixels', 'Position', [40 40 w h]);
tl = tiledlayout(f, rows, cols, 'TileSpacing', 'compact', 'Padding', 'compact');
end

function ax = tile(tl, varargin)
ST = tmpl();
ax = nexttile(tl, varargin{:});
hold(ax, 'on');  box(ax, 'on');  grid(ax, 'off');
set(ax, 'FontName', ST.font, 'FontSize', ST.szTick, 'FontWeight', 'bold', 'LineWidth', ST.boxWidth, ...
    'XColor', ST.ink, 'YColor', ST.ink, 'Color', 'w', 'TickDir', 'in', 'Layer', 'top');
end

function ttl(ax, s)
ST = tmpl();
title(ax, s, 'FontName', ST.font, 'FontSize', ST.szTitle, 'FontWeight', 'bold', 'Color', ST.ink);
end

function lbl(ax, xl, yl)
ST = tmpl();
if ~isempty(xl), xlabel(ax, xl, 'FontName', ST.font, 'FontSize', ST.szLabel, 'FontWeight', 'bold', 'Color', ST.ink); end
if ~isempty(yl), ylabel(ax, yl, 'FontName', ST.font, 'FontSize', ST.szLabel, 'FontWeight', 'bold', 'Color', ST.ink); end
end

function layoutTitle(tl, t, s)
ST = tmpl();
title(tl, t, 'FontName', ST.font, 'FontSize', ST.szSgtitle, 'FontWeight', 'bold', 'Color', ST.ink);
subtitle(tl, s, 'FontName', ST.font, 'FontSize', ST.szSub, 'Color', ST.sub);
end

function lg = leg(ax, h, names, varargin)
ST = tmpl();
lg = legend(ax, h, names, 'FontName', ST.font, 'FontSize', ST.szLegend, 'FontWeight', 'bold', 'TextColor', ST.ink, ...
    'Box', 'on', 'EdgeColor', ST.ink, 'LineWidth', 1.2, 'Color', 'w', 'AutoUpdate', 'off', varargin{:});
end

function h = keyPatch(ax, col)
% Legend key for a bar colour (no data).
ST = tmpl();
h = patch(ax, NaN, NaN, col, 'EdgeColor', ST.edge, 'LineWidth', ST.barEdgeW);
end

function b = hbars(ax, y, v, cols)
% Horizontal bars, one colour row per value (bar colours follow ascending y, so sort first).
ST = tmpl();
cols = repmat(cols, numel(v) / size(cols, 1), 1);
[y, o] = sort(y(:));  v = v(:);
b = barh(ax, y, v(o), 0.7, 'FaceColor', 'flat', 'EdgeColor', ST.edge, 'LineWidth', ST.barEdgeW);
b.CData = cols(o, :);
end

function b = vbars(ax, V, cols)
% Grouped vertical bars (step 9: bar width 0.9 per group, dark outline), one colour per column of V.
ST = tmpl();
b = bar(ax, V, 'grouped', 'BarWidth', 0.85, 'EdgeColor', ST.edge, 'LineWidth', ST.barEdgeW);
for k = 1:numel(b), b(k).FaceColor = cols(k,:); end
end

function refLine(ax, v, dim, txt)
ST = tmpl();
a = {'Color', ST.ref, 'LineWidth', ST.refW, 'HandleVisibility', 'off', 'FontName', ST.font, 'FontSize', ST.szText, 'FontWeight', 'bold'};
if strcmp(dim, 'y')
    yline(ax, v, '--', txt, a{:}, 'LabelHorizontalAlignment', 'right', 'LabelVerticalAlignment', 'bottom');
else
    xline(ax, v, '--', txt, a{:}, 'LabelVerticalAlignment', 'bottom', 'LabelHorizontalAlignment', 'right');
end
end

function evLine(ax, x, txt, ls, va)
% Vertical event line with its label at the top (or va = 'bottom' / 'middle').
if nargin < 4, ls = '-'; end
if nargin < 5, va = 'top'; end
ST = tmpl();
xline(ax, x, ls, txt, 'Color', ST.ref, 'LineWidth', 1.6, 'HandleVisibility', 'off', 'FontName', ST.font, ...
    'FontSize', ST.szText, 'FontWeight', 'bold', 'LabelVerticalAlignment', va, 'LabelHorizontalAlignment', 'left');
end

function labelPoints(ax, x, y, s)
% Labels next to scatter points: right of the point, or left / above / below when that side would
% overlap another label or point. Set the axis limits before calling.
ST = tmpl();  drawnow;
pp = getpixelposition(ax);  xl = xlim(ax);  yl = ylim(ax);
ux = diff(xl) / pp(3);  uy = diff(yl) / pp(4);                     % data units per pixel
r = 9;                                                              % marker radius (px)
boxes = [x(:) - r * ux, y(:) - r * uy, repmat(2 * r * ux, numel(x), 1), repmat(2 * r * uy, numel(x), 1)];
side = {[1 0], 'left', 'middle'; [-1 0], 'right', 'middle'; [0 1], 'center', 'bottom'; [0 -1], 'center', 'top'};
for i = 1:numel(x)
    for c = 1:size(side, 1)
        d = side{c,1} .* [(r + 3) * ux, (r + 2) * uy];
        t = text(ax, x(i) + d(1), y(i) + d(2), s{i}, 'FontName', ST.font, 'FontSize', ST.szText, 'FontWeight', 'bold', ...
            'Color', ST.txt, 'HorizontalAlignment', side{c,2}, 'VerticalAlignment', side{c,3});
        e = t.Extent;  o = setdiff(1:size(boxes, 1), i);
        hit = e(1) < boxes(o,1) + boxes(o,3) & boxes(o,1) < e(1) + e(3) & e(2) < boxes(o,2) + boxes(o,4) & boxes(o,2) < e(2) + e(4);
        if ~any(hit) || c == size(side, 1), boxes(end+1, :) = e; break; end %#ok<AGROW>
        delete(t);
    end
end
end

function valText(ax, x, y, s, varargin)
ST = tmpl();
text(ax, x, y, s, 'FontName', ST.font, 'FontSize', ST.szText, 'FontWeight', 'bold', 'Color', ST.txt, varargin{:});
end

function c = limbColours(names)
% Leading = blue, trailing = orange, both limbs = green, from the feature-set name.
ST = tmpl();  c = repmat(ST.both, numel(names), 1);
isL = contains(names, 'lead');  isT = contains(names, 'trail');
c(isL, :) = repmat(ST.lead, nnz(isL), 1);  c(isT, :) = repmat(ST.trail, nnz(isT), 1);
end

function c = ramp3(base)
% Light / base / dark shades of one colour (H1 / H2 / H3).
c = [base + 0.6 * (1 - base); base; 0.45 * base];
end

function cm = seqMap(base)
% White -> base colour -> dark (heat maps).
t = linspace(0, 1, 128)';
cm = [1 - t * (1 - base); base .* (1 - 0.6 * t)];
end

function s = shortCal(s)
% Shorter labels for the calibration options of crossing_ml_device.m.
s = regexprep(s, '^generic model \((\w+)\), lead-foot clearance-shape features only, level-walk scaling$', 'generic $1, shape features only');
s = regexprep(s, '^generic model \((\w+)\), level-walk scaling$', 'generic $1');
s = regexprep(s, '^person scaling from (the )?(.*) crossings \(forest\)$', 'person scaling, $2 crossings');
s = strrep(s, 'unlabelled crossings (mixture, spacing fixed by physics)', 'unlabelled crossings (physics mixture)');
s = strrep(s, 'offset from the level walk', 'from the level walk');
end

function saveFig(tl, out, name)
% PNG of the tiled layout at the template resolution (step 9 saveFig); toolbars hidden.
ST = tmpl();  f = ancestor(tl, 'figure');
axs = findall(f, 'Type', 'axes');
for a = 1:numel(axs)
    try
        axtoolbar(axs(a), {});
    catch
    end
end
exportgraphics(tl, fullfile(out, name), 'Resolution', ST.pngDPI);
close(f);
end
