clc; clear; close all;
addpath(fileparts(mfilename('fullpath')));
%% ========================================================================
%% DEFINITION FIGURES - illustrate what each group parameter MEANS
%% ========================================================================
% Presentation-ready schematics built from ONE real example participant:
%   1) Obstacle crossing   -> toe & heel sagittal trajectory over the obstacle,
%                             with take-off distance, landing distance, toe clearance.
%   2) Range of motion     -> an example stride (joint + IMU segment) vs % gait cycle,
%                             with max, min and the ROM = max-min span.
%   3) Peak timing         -> an example stride (joint + foot height) vs % gait cycle,
%                             with the peak marked at its % of the cycle.
% Grid OFF, clean, big fonts. PNG only. Not an analysis - just definitions.
% Output -> Results/Group Analysis/Figures/Definitions/

%% ===================== CONFIG =====================
DEF_TEST = 104;                 % participant to pull the clean example from
ROM_JOINT = 'knee_angle';       % joint for the ROM definition
ROM_SEG   = 'Thigh';            % IMU segment for the ROM definition (Dot)
SEG_SYS   = 'Dot';
% -------- style (presentation) --------
FN='Arial'; SZ_T=18; SZ_L=16; SZ_TK=13; SZ_LG=13; SZ_ANN=14; BOXW=2.2; LW=3.2;
C_TOE =[0.17 0.49 0.72]; C_HEEL=[0.89 0.52 0.20]; C_OBS=[0.80 0.80 0.80];
C_DIM =[0.12 0.12 0.12]; C_MAX =[0.85 0.10 0.10]; C_SIG =[0.20 0.40 0.80];

root = fileparts(fileparts(mfilename('fullpath')));
base = fullfile(root,'Results','Parameters Output',['Test ' num2str(DEF_TEST)]);
outDir = fullfile(root,'Results','Group Analysis','Figures','Definitions');
if ~isfolder(outDir), mkdir(outDir); end
CP = load(fullfile(base,sprintf('CrossingParams_Test%d.mat',DEF_TEST)));  CP = CP.CP;
Sg = load(fullfile(base,sprintf('SegmentedParams_Test%d.mat',DEF_TEST))); Sg = Sg.Seg;
S5f = fullfile(base,sprintf('SegTrajectories_WithCamera_Test%d.mat',DEF_TEST));
S5 = load(S5f); fn = fieldnames(S5); S5 = S5.(fn{1});
NSEG = Sg.nseg;  pct = linspace(0,100,NSEG)';

%% ===================== FIG 1 - OBSTACLE CROSSING =====================
% Pick a clear Leading crossing (tallest obstacle, finite arc, good clearance).
e = pickCrossing(CP);
c = CP.crossing(e);  a = c.arc;
w = c.obs_w/10; h = c.obs_h/10;                        % cm
yT=fillmissing(a.yToe/10,'linear','EndValues','nearest');  zT=smoothSig(a.zToe/10);
yH=fillmissing(a.yHeel/10,'linear','EndValues','nearest'); zH=smoothSig(a.zHeel/10);
yb = c.y_toe_begin/10; yl = c.y_heel_land/10; zc = c.z_toe_cross/10;
nearE = -w/2; farE = w/2;

f1 = figure('Color','w','Position',[80 90 1180 680]); ax = axes(f1); hold(ax,'on'); box(ax,'on');
rectangle(ax,'Position',[nearE 0 w h],'FaceColor',C_OBS,'EdgeColor',[0.45 0.45 0.45],'LineWidth',1.5);
hToe  = plot(ax, yT, zT, '-', 'Color',C_TOE,  'LineWidth',LW);
hHeel = plot(ax, yH, zH, '-', 'Color',C_HEEL, 'LineWidth',LW);
plot(ax, 0, zc, 'o', 'Color',C_TOE, 'MarkerFaceColor',C_TOE, 'MarkerSize',9, 'HandleVisibility','off');
styleAx(ax, FN, SZ_TK, BOXW);
allY = [yT(:); yH(:); yb; yl];  allZ = [zT(:); zH(:); h; 0];       % span the WHOLE of both curves
zmin = min(allZ);  zmax = max(allZ);
band = max(16, (zmax-zmin)*0.24);                                  % clear band below the curves for dim lines
ylim(ax,[zmin-band, zmax*1.15 + 2]);  xlim(ax, [min(allY)-8, max(allY)+8]);
dz = zmin - band*0.5;                                              % take-off / landing dimension-line level
dimH(ax, yb, nearE, dz, sprintf('take-off %.0f cm', c.lift_dist/10), C_DIM, FN, SZ_ANN);
dimH(ax, farE, yl, dz, sprintf('landing %.0f cm', c.land_dist/10), C_DIM, FN, SZ_ANN);
dimV(ax, 0, h, zc, sprintf('toe clearance %.0f cm', c.clr_toe/10), C_MAX, FN, SZ_ANN);
text(ax, 0, h/2, 'obstacle', 'HorizontalAlignment','center','FontName',FN,'FontSize',SZ_ANN-1,'Color',[0.30 0.30 0.30],'FontWeight','bold');
xlabel(ax,'Horizontal position from obstacle centre (cm)','FontName',FN,'FontSize',SZ_L,'FontWeight','bold');
ylabel(ax,'Height (cm)','FontName',FN,'FontSize',SZ_L,'FontWeight','bold');
title(ax, 'Obstacle crossing — clearance & foot placement', ...
    'FontName',FN,'FontSize',SZ_T,'FontWeight','bold','Interpreter','none');
legend([hToe hHeel], {'Toe trajectory','Heel trajectory'}, 'Location','northeast','FontName',FN,'FontSize',SZ_LG);
savePNGdef(f1, outDir, 'def_Crossing');

%% ===================== FIG 2 - RANGE OF MOTION =====================
yJ = meanCrossStride(Sg, S5, sprintf('Joint: %s_r', ROM_JOINT));
if all(isnan(yJ)), yJ = meanCrossStride(Sg, S5, sprintf('Joint: %s_l', ROM_JOINT)); end
yS = meanCrossStride(Sg, S5, sprintf('IMU: Right %s (%s) X', ROM_SEG, SEG_SYS));
if all(isnan(yS)), yS = meanCrossStride(Sg, S5, sprintf('IMU: Left %s (%s) X', ROM_SEG, SEG_SYS)); end
yJ = smoothSig(yJ);  yS = smoothSig(yS);

f2 = figure('Color','w','Position',[70 90 1300 540]);
tl = tiledlayout(f2,1,2,'TileSpacing','compact','Padding','compact');
drawROMpanel(nexttile(tl), pct, yJ, titleCase(ROM_JOINT), FN,SZ_T,SZ_L,SZ_TK,SZ_ANN,BOXW,LW,C_SIG,C_DIM);
drawROMpanel(nexttile(tl), pct, yS, sprintf('%s segment (IMU)', ROM_SEG), FN,SZ_T,SZ_L,SZ_TK,SZ_ANN,BOXW,LW,C_SIG,C_DIM);
title(tl,'Range of motion  =  max − min  (over one crossing stride)','FontName',FN,'FontSize',SZ_T,'FontWeight','bold');
savePNGdef(f2, outDir, 'def_ROM');

%% ===================== FIG 3 - PEAK ANGLE VARIABLES =====================
% Each named peak = an EXCURSION from the stance (begin-ZVP) reference. One panel
% per signal, for the limb where it reads best; peaks coloured red (primary) /
% green (secondary). {signal, kind, role(example limb), nice, {name, ext, PorS}...}
C_LEAD = [0.17 0.49 0.72];  C_TRAIL = [0.89 0.52 0.20];  C_REF = [0.35 0.35 0.35];
PANELS = {   % signal, kind, nice, {peak name, ext, P/S}
 'hip_flexion','Joint','Hip',   { 'Hip peak flexion','min','P';   'Hip peak extension','max','S' };
 'knee_angle', 'Joint','Knee',  { 'Knee peak flexion','min','P' };
 'ankle_angle','Joint','Ankle', { 'Ankle dorsiflexion','max','P'; 'Ankle plantarflexion','min','P' };
 'Thigh',      'Seg',  'Thigh', { 'Thigh forward tilt','max','P'; 'Thigh backward tilt','min','S' };
 'Shank',      'Seg',  'Shank', { 'Shank backward (heel up)','min','P'; 'Shank forward (reach)','max','S' };
 'Foot',       'Seg',  'Foot',  { 'Foot toe-down','min','P';     'Foot toe-up','max','S' };
};
f3 = figure('Color','w','Position',[30 40 1760 940]);
tl3 = tiledlayout(f3,2,3,'TileSpacing','compact','Padding','compact');
for i = 1:size(PANELS,1)
    sig = PANELS{i,1};  kind = PANELS{i,2};
    yL = smoothSig(meanCrossStrideRole(Sg, S5, sig, kind, 'Leading',  SEG_SYS));
    yT = smoothSig(meanCrossStrideRole(Sg, S5, sig, kind, 'Trailing', SEG_SYS));
    drawPeakDef(nexttile(tl3), pct, yL, yT, PANELS{i,3}, PANELS{i,4}, i==1, ...
        FN,SZ_T,SZ_L,SZ_TK,SZ_ANN,BOXW,LW,C_LEAD,C_TRAIL,C_REF);
end
title(tl3,'Peak angle variables  =  excursion from stance (begin-ZVP).   Leading (blue) vs Trailing (orange); values in degrees', ...
    'FontName',FN,'FontSize',SZ_T,'FontWeight','bold');
savePNGdef(f3, outDir, 'def_PeakAngles');

fprintf('Definition figures saved -> %s\n', outDir);

%% ============================ functions ============================
function e = pickCrossing(CP)
% A clear Leading crossing: tallest obstacle, finite arc, largest toe clearance.
    best = 1; bestScore = -inf;
    for i = 1:numel(CP.crossing)
        c = CP.crossing(i);
        if ~strcmpi(c.role,'Leading'), continue; end
        if isempty(c.arc) || all(isnan(c.arc.zToe)), continue; end
        score = c.obs_h + max(0,c.clr_toe);
        if score > bestScore, bestScore = score; best = i; end
    end
    e = best;
end

function m = meanCrossStride(Sg, S5, label)
% Mean normalized stride (NSEG x 1) over this signal's OBSTACLE-crossing strides.
    m = nan(Sg.nseg,1);
    k = find(strcmp({Sg.signal.label}, label), 1);  if isempty(k), return; end
    Y = Sg.signal(k).strides;  sd = Sg.signal(k).side;
    if sd=='R', T=S5.camera.terrainR; R=S5.camera.roleR; else, T=S5.camera.terrainL; R=S5.camera.roleL; end
    sel = false(1, size(Y,2));
    for j = 1:min(size(Y,2), numel(T))
        if ~isempty(T{j}) && ~strcmpi(T{j},'Level_Walk') && ~isempty(R{j}), sel(j) = true; end
    end
    if any(sel), m = mean(Y(:,sel), 2, 'omitnan'); end
end

function drawROMpanel(ax, pct, y, ttl, FN,SZ_T,SZ_L,SZ_TK,SZ_ANN,BOXW,LW,cSig,cDim)
    hold(ax,'on'); box(ax,'on');
    plot(ax, pct, y, '-', 'Color',cSig, 'LineWidth',LW);
    [mx,ix]=max(y); [mn,in]=min(y);  rng=mx-mn;
    plot(ax, pct(ix), mx, 'o','Color',cDim,'MarkerFaceColor',cDim,'MarkerSize',8);
    plot(ax, pct(in), mn, 'o','Color',cDim,'MarkerFaceColor',cDim,'MarkerSize',8);
    yline(ax, mx, ':','Color',cDim,'LineWidth',1.2); yline(ax, mn, ':','Color',cDim,'LineWidth',1.2);
    styleAx(ax, FN, SZ_TK, BOXW);
    xlim(ax,[-4 128]);  ylim(ax,[mn-rng*0.18, mx+rng*0.18]);   % pad so curve + ROM label fully fit
    dimV(ax, 105, mx, mn, sprintf('ROM = %.0f°', rng), cDim, FN, SZ_ANN);
    text(ax, pct(ix), mx, '  max','FontName',FN,'FontSize',SZ_ANN-1,'FontWeight','bold','Color',cDim,'VerticalAlignment','bottom');
    text(ax, pct(in), mn, '  min','FontName',FN,'FontSize',SZ_ANN-1,'FontWeight','bold','Color',cDim,'VerticalAlignment','top');
    xlabel(ax,'Gait cycle (%)','FontName',FN,'FontSize',SZ_L,'FontWeight','bold');
    ylabel(ax,'angle (deg)','FontName',FN,'FontSize',SZ_L,'FontWeight','bold');
    title(ax, ttl,'FontName',FN,'FontSize',SZ_T,'FontWeight','bold','Interpreter','none');
end

function drawPeakDef(ax, pct, yL, yT, ttl, peaks, showLeg, FN,SZ_T,SZ_L,SZ_TK,SZ_ANN,BOXW,LW,cLead,cTrail,cRef)
% Define named peaks on a signal, Leading (blue) vs Trailing (orange). Each curve
% has its own stance (begin-ZVP) reference; every named peak is marked on BOTH
% curves as an excursion, labelled with the value used (name once on Leading).
    hold(ax,'on'); box(ax,'on');
    hL = plot(ax, pct, yL, '-', 'Color',cLead,  'LineWidth',LW);
    hT = plot(ax, pct, yT, '-', 'Color',cTrail, 'LineWidth',LW);
    styleAx(ax, FN, SZ_TK, BOXW);
    refL = median(yL(1:min(4,numel(yL))),'omitnan');  refT = median(yT(1:min(4,numel(yT))),'omitnan');
    yline(ax, refL, ':', 'stance', 'Color',cRef, 'LineWidth',1.4, 'FontName',FN, 'FontSize',max(9,SZ_ANN-3), ...
        'LabelHorizontalAlignment','right', 'LabelVerticalAlignment','bottom');
    allY = [yL;yT];  rng = max(max(allY)-min(allY), eps);
    ylim(ax,[min(allY)-rng*0.22, max(allY)+rng*0.30]);  xlim(ax,[-3 103]);
    fs = max(10, SZ_ANN-3);
    for p = 1:size(peaks,1)
        nm = peaks{p,1};  ext = peaks{p,2};
        if strcmpi(ext,'min'), [vL,iL]=min(yL); [vT,iT]=min(yT);  va='top'; else, [vL,iL]=max(yL); [vT,iT]=max(yT);  va='bottom'; end
        % Leading
        plot(ax, [pct(iL) pct(iL)], [refL vL], '-', 'Color',cLead, 'LineWidth',2.2);
        plot(ax, pct(iL), vL, 'o','Color',cLead,'MarkerFaceColor',cLead,'MarkerSize',9);
        haL = 'left'; if pct(iL) > 55, haL = 'right'; end
        text(ax, pct(iL), vL, sprintf(' %s  L %.0f° ', nm, abs(vL-refL)), 'HorizontalAlignment',haL,'VerticalAlignment',va, ...
            'FontName',FN,'FontSize',fs,'FontWeight','bold','Color',cLead);
        % Trailing
        plot(ax, [pct(iT) pct(iT)], [refT vT], '-', 'Color',cTrail, 'LineWidth',2.2);
        plot(ax, pct(iT), vT, 'o','Color',cTrail,'MarkerFaceColor',cTrail,'MarkerSize',9);
        haT = 'left'; if pct(iT) > 55, haT = 'right'; end
        text(ax, pct(iT), vT, sprintf(' T %.0f° ', abs(vT-refT)), 'HorizontalAlignment',haT,'VerticalAlignment',va, ...
            'FontName',FN,'FontSize',fs,'FontWeight','bold','Color',cTrail);
    end
    xlabel(ax,'Gait cycle (%)','FontName',FN,'FontSize',SZ_L,'FontWeight','bold');
    ylabel(ax,'angle (deg)','FontName',FN,'FontSize',SZ_L,'FontWeight','bold');
    title(ax, ttl,'FontName',FN,'FontSize',SZ_T,'FontWeight','bold','Interpreter','none');
    if showLeg, legend([hL hT], {'Leading','Trailing'}, 'Location','best', 'FontName',FN,'FontSize',SZ_L-2); end
end

function m = meanCrossStrideRole(Sg, S5, sig, kind, role, segSys)
% Mean crossing-stride curve for a signal, pooled over BOTH limbs' strides that
% had the given role (Leading/Trailing).
    cols = [];
    for sd = {'L','R'}
        s = sd{1};
        if strcmp(kind,'Joint'), lbl = sprintf('Joint: %s_%s', sig, lower(s));
        else,                    lbl = sprintf('IMU: %s %s (%s) X', sideWord(s), sig, segSys);
        end
        k = find(strcmp({Sg.signal.label}, lbl), 1);  if isempty(k), continue; end
        Y = Sg.signal(k).strides;
        if s=='R', R = S5.camera.roleR; else, R = S5.camera.roleL; end
        sel = false(1, size(Y,2));
        for j = 1:min(size(Y,2), numel(R)), if strcmpi(R{j}, role), sel(j) = true; end, end
        cols = [cols, Y(:,sel)]; %#ok<AGROW>
    end
    if isempty(cols), m = nan(Sg.nseg,1); else, m = mean(cols, 2, 'omitnan'); end
end

function w = sideWord(s)
    if s=='R', w = 'Right'; else, w = 'Left'; end
end

function y = smoothSig(y)
% Gentle zero-phase low-pass so the representative curve reads smoothly.
    y = y(:);
    if sum(~isnan(y)) < 8, return; end
    y = fillmissing(y,'linear','EndValues','nearest');
    try
        [b,a] = butter(4, 0.12);          % fraction of Nyquist (normalized stride)
        y = filtfilt(b,a,y);
    catch
        y = smoothdata(y,'gaussian',max(5,round(numel(y)*0.06)));
    end
end

function dimH(ax, x1, x2, y, label, col, FN, fs)
% Horizontal dimension line with end ticks + centred label.
    tick = diff(ylim(ax))*0.02;
    plot(ax, [x1 x2], [y y], '-', 'Color',col, 'LineWidth',2);
    plot(ax, [x1 x1], y+[-tick tick], '-', 'Color',col,'LineWidth',2);
    plot(ax, [x2 x2], y+[-tick tick], '-', 'Color',col,'LineWidth',2);
    text(ax, (x1+x2)/2, y+tick*2.2, label, 'HorizontalAlignment','center','VerticalAlignment','bottom', ...
        'FontName',FN,'FontSize',fs,'FontWeight','bold','Color',col,'BackgroundColor','w','Margin',1);
end

function dimV(ax, x, y1, y2, label, col, FN, fs)
% Vertical dimension line with end ticks + label.
    tick = diff(xlim(ax))*0.015;
    plot(ax, [x x], [y1 y2], '-', 'Color',col, 'LineWidth',2);
    plot(ax, x+[-tick tick], [y1 y1], '-', 'Color',col,'LineWidth',2);
    plot(ax, x+[-tick tick], [y2 y2], '-', 'Color',col,'LineWidth',2);
    text(ax, x+tick*2, (y1+y2)/2, label, 'HorizontalAlignment','left','FontName',FN,'FontSize',fs, ...
        'FontWeight','bold','Color',col,'BackgroundColor','w','Margin',1);
end

function styleAx(ax, FN, tk, boxw)
    ax.FontName=FN; ax.FontSize=tk; ax.FontWeight='bold'; ax.LineWidth=boxw; ax.Box='on';
    grid(ax,'off'); ax.XColor=[0.15 0.15 0.15]; ax.YColor=[0.15 0.15 0.15];
end

function s = titleCase(name)
    s = strrep(name,'_',' ');
end

function savePNGdef(f, outDir, name)
    axs = findall(f,'Type','axes');
    for a=1:numel(axs)
        if ~isempty(axs(a).Toolbar), axs(a).Toolbar.Visible='off'; end
    end
    exportgraphics(f, fullfile(outDir,[name '.png']), 'Resolution',300);
end
