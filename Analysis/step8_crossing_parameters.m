clc
close all
addpath(fileparts(mfilename('fullpath')));

%% ========================================================================
%% STEP 8 - Obstacle-crossing parameters (clearance & foot placement)
%% ========================================================================
% For every obstacle-crossing gait cycle (ZVP -> ZVP, from the IMU), read the
% CAMERA foot-marker positions at the key moments and report 6 parameters per
% crossing (toe & heel). The obstacle CENTRE is y = 0 in the trajectory frame.
%
%   begin-ZVP moment (foot settled BEFORE the obstacle):  y_toe , y_heel
%   land-ZVP  moment (foot settled AFTER  the obstacle):  y_toe , y_heel
%   y = 0 crossing (marker passing over the obstacle):    z_toe , z_heel
%
% ZVP moments come from the IMU (step 4); positions come from the camera
% (step 5). Which cycles are crossings, and each leg's Leading/Trailing role,
% come from step 7's per-cycle labels. Two outputs: (1) a z-vs-y figure of the
% crossing arcs with the 6 moment-markers, split Leading vs Trailing; (2) bar
% plots of each parameter grouped by Terrain x Leading/Trailing. (Obstacle
% heights, for true clearance = z - top, come later.)
%
% Inputs (run first): CameraSynced_TestN.mat (step 5), SegmentedParams_TestN.mat
% (step 4), SegTrajectories_WithCamera_TestN.mat (step 7).

%% ===================== SETTINGS =====================
% Terrain groups use the step-3/step-7 code = W{width}_H{height} (width first).
TERRAIN_ORDER = {'Level_Walk','W1_H1','W1_H2','W1_H3','W2_H1','W2_H2','W2_H3'};
ZVP_NEAR_W = 5;         % if a marker is NaN at the exact ZVP frame, use nearest finite within +/- this
FONT_NAME  = 'Arial';

%% ===================== INPUT + LOAD =====================
if exist('TN','var') && ~isempty(TN), tn = TN; else, tn = input('  Input Test Number: '); end
root = fileparts(fileparts(mfilename('fullpath')));
base = fullfile(root, 'Results','Parameters Output', ['Test ' num2str(tn)]);
if ~isfolder(base)
    base2 = fullfile('..','Results','Parameters Output', ['Test ' num2str(tn)]);
    if isfolder(base2), base = base2; end
end
camFile = fullfile(base, sprintf('CameraSynced_Test%d.mat', tn));
segFile = fullfile(base, sprintf('SegmentedParams_Test%d.mat', tn));
s5File  = fullfile(base, sprintf('SegTrajectories_WithCamera_Test%d.mat', tn));
if ~isfile(camFile), error('Not found: %s  (run step 5 for Test %d).', camFile, tn); end
if ~isfile(segFile), error('Not found: %s  (run step 4 for Test %d).', segFile, tn); end
if ~isfile(s5File),  error('Not found: %s  (run step 7 for Test %d).', s5File, tn); end
load(camFile,'Cam');  load(segFile,'Seg');  load(s5File,'S5');
obsTerr = TERRAIN_ORDER(~strcmp(TERRAIN_ORDER,'Level_Walk'));
tcol = terrainColors(obsTerr);

zvp   = struct('L', Seg.zvpL(:), 'R', Seg.zvpR(:));
terrC = struct('L', {S5.camera.terrainL}, 'R', {S5.camera.terrainR});
roleC = struct('L', {S5.camera.roleL},    'R', {S5.camera.roleR});

% Obstacle heights (mm) for H1/H2/H3 - provide EITHER of:
%   (a) leg length in cm (ONE number)      -> H1/H2/H3 = 10/20/30% of leg length
%   (b) the three heights in cm as [h1 h2 h3] -> used directly as H1/H2/H3
% Widths are fixed: W1 = 5 cm (50 mm), W2 = 15 cm (150 mm). Obstacle CENTRED at y=0.
% Batch: set LEGLEN_CM (a single number) or HEIGHTS_CM ([h1 h2 h3]) before running.
if     exist('HEIGHTS_CM','var') && ~isempty(HEIGHTS_CM), hin = HEIGHTS_CM(:)';
elseif exist('LEGLEN_CM','var')  && ~isempty(LEGLEN_CM),  hin = LEGLEN_CM;
else,  hin = input('  Leg length in cm (one number)  OR  the 3 heights in cm as [h1 h2 h3]: ');
end
hin = hin(:)';
if isscalar(hin)
    legLen_cm = hin;  heights_mm = [0.10 0.20 0.30] * (hin*10);
    fprintf('Leg length %.1f cm -> obstacle heights H1=%.0f H2=%.0f H3=%.0f mm; widths W1=50 W2=150 mm\n', ...
            legLen_cm, heights_mm(1), heights_mm(2), heights_mm(3));
elseif numel(hin) == 3
    legLen_cm = NaN;  heights_mm = hin * 10;    % cm -> mm, used directly
    fprintf('Given heights -> H1=%.0f H2=%.0f H3=%.0f mm; widths W1=50 W2=150 mm\n', ...
            heights_mm(1), heights_mm(2), heights_mm(3));
else
    error('Enter ONE number (leg length in cm) or THREE heights [h1 h2 h3] in cm.');
end

%% ===================== EXTRACT PARAMETERS PER CROSSING =====================
% X = struct array, one entry per obstacle-crossing cycle.
X = struct('side',{},'terrain',{},'role',{},'cyc',{}, ...
           'y_toe_begin',{},'y_heel_begin',{},'y_toe_land',{},'y_heel_land',{}, ...
           'z_toe_cross',{},'z_heel_cross',{}, ...
           'z_toe_begin',{},'z_heel_begin',{},'z_toe_land',{},'z_heel_land',{}, ...
           'obs_h',{},'obs_w',{},'lift_dist',{},'land_dist',{},'clr_toe',{},'clr_heel',{},'arc',{});
for side = {'L','R'}
    sd = side{1};
    z  = zvp.(sd);  tr = terrC.(sd);  rl = roleC.(sd);
    Mtoe  = Cam.markers.([sd '_toe']);   Mheel = Cam.markers.([sd '_heel']);
    for c = 1:numel(tr)
        Tn = ''; if iscell(tr), Tn = tr{c}; end
        if isempty(Tn) || strcmpi(Tn,'Level_Walk'), continue; end   % crossings only
        Rl = ''; if iscell(rl), Rl = rl{c}; end
        i0 = z(c); i1 = z(c+1);  idx = i0:i1;
        yToe = Mtoe(idx,2); zToe = Mtoe(idx,3); yHeel = Mheel(idx,2); zHeel = Mheel(idx,3);
        e = numel(X)+1;
        X(e).side = sd;  X(e).terrain = Tn;  X(e).role = Rl;  X(e).cyc = c;
        X(e).y_toe_begin  = sampleNear(Mtoe, i0, 2, ZVP_NEAR_W);
        X(e).y_heel_begin = sampleNear(Mheel,i0, 2, ZVP_NEAR_W);
        X(e).y_toe_land   = sampleNear(Mtoe, i1, 2, ZVP_NEAR_W);
        X(e).y_heel_land  = sampleNear(Mheel,i1, 2, ZVP_NEAR_W);
        X(e).z_toe_cross  = zAtY0(yToe,  zToe);
        X(e).z_heel_cross = zAtY0(yHeel, zHeel);
        X(e).z_toe_begin  = sampleNear(Mtoe, i0, 3, ZVP_NEAR_W);
        X(e).z_heel_begin = sampleNear(Mheel,i0, 3, ZVP_NEAR_W);
        X(e).z_toe_land   = sampleNear(Mtoe, i1, 3, ZVP_NEAR_W);
        X(e).z_heel_land  = sampleNear(Mheel,i1, 3, ZVP_NEAR_W);
        % --- clearance parameters (obstacle centred at y=0; approach edge -w/2, far edge +w/2) ---
        [hgt, w] = obstacleGeom(Tn, heights_mm);  nearEdge = -w/2;  farEdge = w/2;
        X(e).obs_h = hgt;  X(e).obs_w = w;
        X(e).lift_dist = nearEdge - X(e).y_toe_begin;   % toe (begin ZVP) -> APPROACH edge (-w/2) (mm)
        X(e).land_dist = X(e).y_heel_land - farEdge;    % heel (land ZVP) -> FAR edge (+w/2) (mm)
        X(e).clr_toe   = X(e).z_toe_cross  - hgt;        % toe  height clearance at y=0 (mm)
        X(e).clr_heel  = X(e).z_heel_cross - hgt;        % heel height clearance at y=0 (mm)
        X(e).arc = struct('t',Cam.time(idx),'yToe',yToe,'zToe',zToe,'yHeel',yHeel,'zHeel',zHeel);
    end
end
nX = numel(X);
fprintf('\nFound %d obstacle-crossing cycles (%d Left, %d Right).\n', nX, ...
        sum(strcmp({X.side},'L')), sum(strcmp({X.side},'R')));

%% ===================== PRINT SUMMARY =====================
PN = {'y_toe_begin','y_heel_begin','y_toe_land','y_heel_land','z_toe_cross','z_heel_cross'};
fprintf('\n%-16s %-9s %-9s | %8s %8s %8s %8s %8s %8s\n','terrain','side','role',PN{:});
for e = 1:nX
    fprintf('%-16s %-9s %-9s | %8.1f %8.1f %8.1f %8.1f %8.1f %8.1f\n', X(e).terrain, X(e).side, X(e).role, ...
        X(e).y_toe_begin, X(e).y_heel_begin, X(e).y_toe_land, X(e).y_heel_land, X(e).z_toe_cross, X(e).z_heel_cross);
end

%% ===================== SAVE =====================
CP = struct('test',tn,'legLen_cm',legLen_cm,'heights_mm',heights_mm,'params',{PN}, ...
            'units','mm (y=walking from obstacle centre, z=height; clearance = z@y=0 - obstacle top)','crossing',X);
save(fullfile(base, sprintf('CrossingParams_Test%d.mat', tn)), 'CP');
Trow = table({X.side}', {X.terrain}', {X.role}', [X.y_toe_begin]', [X.y_heel_begin]', ...
             [X.y_toe_land]', [X.y_heel_land]', [X.z_toe_cross]', [X.z_heel_cross]', ...
             [X.obs_h]', [X.obs_w]', [X.lift_dist]', [X.land_dist]', [X.clr_toe]', [X.clr_heel]', ...
             'VariableNames', [{'side','terrain','role'}, PN, {'obs_h','obs_w','lift_dist','land_dist','clr_toe','clr_heel'}]);
outXls = fullfile(base, sprintf('CrossingParams_Test%d.xlsx', tn));
if isfile(outXls), delete(outXls); end
writetable(Trow, outXls, 'Sheet','crossings');
fprintf('\nSaved CrossingParams_Test%d .mat/.xlsx\n', tn);

%% ===================== FIGURE 1 - interactive z vs y crossing arcs =====================
f1 = buildArcViewer(X, obsTerr, tcol, tn, base, heights_mm, FONT_NAME);
exportgraphics(f1, fullfile(base, sprintf('CrossingArcs_Test%d.png', tn)), 'Resolution', 200);

%% ===================== FIGURE 2 - bar plots (Terrain x Leading/Trailing) =====================
f2 = figure('Color','w','Name',sprintf('Step 8 - crossing parameters | Test %d', tn),'Position',[80 60 1500 820]);
ylabs = {'y toe @begin (mm)','y heel @begin (mm)','y toe @land (mm)','y heel @land (mm)','z toe @y=0 (mm)','z heel @y=0 (mm)'};
for pi = 1:6
    ax = subplot(2,3,pi); hold(ax,'on'); grid(ax,'on'); box(ax,'on');
    gL = cell(1,numel(obsTerr)); gR = cell(1,numel(obsTerr));
    for ti = 1:numel(obsTerr)
        for e = 1:nX
            if ~strcmp(X(e).terrain, obsTerr{ti}), continue; end
            v = X(e).(PN{pi});
            if strcmp(X(e).role,'Leading'), gL{ti}(end+1)=v; elseif strcmp(X(e).role,'Trailing'), gR{ti}(end+1)=v; end
        end
    end
    drawGrouped(ax, obsTerr, gL, gR, ylabs{pi}, PN{pi}, FONT_NAME);
end
exportgraphics(f2, fullfile(base, sprintf('CrossingParamsBars_Test%d.png', tn)), 'Resolution', 200);

%% ===================== FIGURE 3 - clearance parameters =====================
% Per terrain x role: lift distance, landing distance, height clearance (toe & heel).
z = cell(1,numel(obsTerr));
gLiftL=z; gLiftR=z; gLandL=z; gLandR=z; cToeL=z; cToeR=z; cHeelL=z; cHeelR=z;
for ti = 1:numel(obsTerr)
    for e = 1:nX
        if ~strcmp(X(e).terrain, obsTerr{ti}), continue; end
        if strcmp(X(e).role,'Leading')
            gLiftL{ti}(end+1)=X(e).lift_dist; gLandL{ti}(end+1)=X(e).land_dist;
            cToeL{ti}(end+1)=X(e).clr_toe; cHeelL{ti}(end+1)=X(e).clr_heel;
        elseif strcmp(X(e).role,'Trailing')
            gLiftR{ti}(end+1)=X(e).lift_dist; gLandR{ti}(end+1)=X(e).land_dist;
            cToeR{ti}(end+1)=X(e).clr_toe; cHeelR{ti}(end+1)=X(e).clr_heel;
        end
    end
end
BLU=[0.20 0.45 0.80]; ORA=[0.85 0.45 0.20]; BLU2=[0.55 0.70 0.95]; ORA2=[0.95 0.72 0.50];
f3 = figure('Color','w','Name',sprintf('Step 8 - clearance parameters | Test %d', tn),'Position',[60 60 1500 480]);
drawGroupedN(subplot(1,3,1), obsTerr, {gLiftL,gLiftR}, {'Leading','Trailing'}, {BLU,ORA}, ...
    'Lift: toe -> approach edge (mm)', 'Lift distance', FONT_NAME);
drawGroupedN(subplot(1,3,2), obsTerr, {gLandL,gLandR}, {'Leading','Trailing'}, {BLU,ORA}, ...
    'Landing: heel -> far edge (mm)', 'Landing distance', FONT_NAME);
drawGroupedN(subplot(1,3,3), obsTerr, {cToeL,cToeR,cHeelL,cHeelR}, {'Lead toe','Trail toe','Lead heel','Trail heel'}, ...
    {BLU,ORA,BLU2,ORA2}, 'clearance z@y=0 - top (mm)', 'Height clearance at obstacle centre', FONT_NAME);
exportgraphics(f3, fullfile(base, sprintf('CrossingClearanceBars_Test%d.png', tn)), 'Resolution', 200);
fprintf('Saved CrossingArcs / CrossingParamsBars / CrossingClearanceBars PNGs.\nDone.\n');

%% ========================================================================
%  LOCAL FUNCTIONS
%% ========================================================================
function v = sampleNear(M, idx, col, W)
% Value at M(idx,col); if NaN, nearest finite within +/- W frames; else NaN.
    n = size(M,1);
    if idx < 1 || idx > n, v = NaN; return; end
    v = M(idx,col);
    if ~isnan(v), return; end
    for d = 1:W
        if idx-d >= 1 && ~isnan(M(idx-d,col)), v = M(idx-d,col); return; end
        if idx+d <= n && ~isnan(M(idx+d,col)), v = M(idx+d,col); return; end
    end
    v = NaN;
end

function z0 = zAtY0(y, z)
% Height where y passes through 0 within the cycle, at the zero-crossing nearest
% the swing apex (max z). Linear interp between the bracketing finite samples.
    z0 = NaN;
    good = isfinite(y) & isfinite(z);
    y = y(good); z = z(good);
    if numel(y) < 2, return; end
    sc = find(sign(y(1:end-1)) .* sign(y(2:end)) < 0);   % sign changes
    if isempty(sc)
        k0 = find(y==0,1); if ~isempty(k0), z0 = z(k0); end
        return;
    end
    [~, zmax] = max(z);
    [~, pick] = min(abs(sc - zmax));  k = sc(pick);
    y1 = y(k); y2 = y(k+1); z1 = z(k); z2 = z(k+1);
    z0 = z1 + (0 - y1)/(y2 - y1) * (z2 - z1);
end

function hF = buildArcViewer(X, obsTerr, tcol, tn, base, heights, fn)
% Interactive z-vs-y crossing arcs. Toggle Terrain, Leading/Trailing, Toe/Heel,
% moment markers, and the symbolic obstacle. Leading = solid, Trailing = dashed;
% toe = thick, heel = thin. Moments: o begin-ZVP, square land-ZVP, diamond z@y=0.
    nT = numel(obsTerr);
    hF = figure('Color','w','Name',sprintf('Step 8 - crossing arcs (z vs y) | Test %d', tn),'Position',[60 70 1380 800]);
    ax = axes(hF,'Position',[0.24 0.10 0.72 0.82]); hold(ax,'on'); grid(ax,'on'); box(ax,'on');
    LX = 0.012; W = 0.20;
    uicontrol(hF,'Style','text','Units','normalized','Position',[LX 0.955 W 0.025],'String','Role  (solid=Lead, dashed=Trail):', ...
        'BackgroundColor','w','FontName',fn,'FontWeight','bold','HorizontalAlignment','left');
    roleCb(1) = uicontrol(hF,'Style','checkbox','Units','normalized','Position',[LX 0.928 0.10 0.026],'String','Leading','Value',1,'BackgroundColor','w','FontName',fn,'Callback',@(~,~) updArc(hF));
    roleCb(2) = uicontrol(hF,'Style','checkbox','Units','normalized','Position',[LX+0.10 0.928 0.10 0.026],'String','Trailing','Value',1,'BackgroundColor','w','FontName',fn,'Callback',@(~,~) updArc(hF));
    uicontrol(hF,'Style','text','Units','normalized','Position',[LX 0.895 W 0.025],'String','Marker  (thick=toe, thin=heel):', ...
        'BackgroundColor','w','FontName',fn,'FontWeight','bold','HorizontalAlignment','left');
    mkCb(1) = uicontrol(hF,'Style','checkbox','Units','normalized','Position',[LX 0.868 0.10 0.026],'String','Toe','Value',1,'BackgroundColor','w','FontName',fn,'Callback',@(~,~) updArc(hF));
    mkCb(2) = uicontrol(hF,'Style','checkbox','Units','normalized','Position',[LX+0.10 0.868 0.10 0.026],'String','Heel','Value',0,'BackgroundColor','w','FontName',fn,'Callback',@(~,~) updArc(hF));
    momCb = uicontrol(hF,'Style','checkbox','Units','normalized','Position',[LX 0.835 0.13 0.026],'String','Moment markers','Value',1,'BackgroundColor','w','FontName',fn,'Callback',@(~,~) updArc(hF));
    obsCb = uicontrol(hF,'Style','checkbox','Units','normalized','Position',[LX 0.805 0.13 0.026],'String','Obstacle','Value',1,'BackgroundColor','w','FontName',fn,'Callback',@(~,~) updArc(hF));
    uicontrol(hF,'Style','pushbutton','Units','normalized','Position',[LX 0.770 0.095 0.028],'String','Save PNG','FontName',fn,'Callback',@(~,~) savePNGarc(hF));
    pnl = uipanel(hF,'Title','Terrain','Units','normalized','Position',[LX 0.03 W 0.72],'BackgroundColor','w','FontName',fn,'FontSize',10,'FontWeight','bold');
    rh = 1/max(nT,1); terCb = gobjects(nT,1);
    for i = 1:nT
        terCb(i) = uicontrol(pnl,'Style','checkbox','Units','normalized','Position',[0.06 1-i*rh 0.9 rh*0.85], ...
            'String',obsTerr{i},'Value',1,'ForegroundColor',tcol(obsTerr{i}),'BackgroundColor','w', ...
            'FontName',fn,'FontSize',10,'FontWeight','bold','Callback',@(~,~) updArc(hF));
    end
    S = struct('ax',ax,'X',X,'obsTerr',{obsTerr},'tcol',tcol,'roleCb',roleCb,'mkCb',mkCb, ...
               'momCb',momCb,'obsCb',obsCb,'terCb',terCb,'heights',heights,'fn',fn,'tn',tn,'base',base);
    guidata(hF, S); updArc(hF);
end

function updArc(hF)
    S = guidata(hF); ax = S.ax; cla(ax); hold(ax,'on');
    showLead = S.roleCb(1).Value==1; showTrail = S.roleCb(2).Value==1;
    showToe = S.mkCb(1).Value==1;  showHeel = S.mkCb(2).Value==1;
    showMom = S.momCb.Value==1;    showObs = S.obsCb.Value==1;
    terOn = arrayfun(@(h) h.Value==1, S.terCb);
    % --- symbolic obstacle rectangles (one per shown terrain), drawn first ---
    if showObs
        for ti = 1:numel(S.obsTerr)
            if ~terOn(ti), continue; end
            [hgt, w] = obstacleGeom(S.obsTerr{ti}, S.heights);  c = S.tcol(S.obsTerr{ti});
            patch(ax, [-w/2 w/2 w/2 -w/2], [0 0 hgt hgt], c, 'FaceAlpha',0.18, 'EdgeColor',c, 'LineWidth',1.4);
        end
    end
    xline(ax,0,'k-','LineWidth',1.2);                       % obstacle centre y=0
    legT = {}; legH = [];
    for e = 1:numel(S.X)
        Xe = S.X(e);
        ti = find(strcmp(S.obsTerr, Xe.terrain),1);  if isempty(ti) || ~terOn(ti), continue; end
        if strcmp(Xe.role,'Leading')  && ~showLead,  continue; end
        if strcmp(Xe.role,'Trailing') && ~showTrail, continue; end
        c = S.tcol(Xe.terrain); A = Xe.arc; hh = [];
        ls = '-'; if strcmp(Xe.role,'Trailing'), ls = '--'; end   % leading solid, trailing dashed
        if showToe
            hh = plot(ax, A.yToe, A.zToe, ls, 'Color', c, 'LineWidth', 2.0);   % toe = thick
            if showMom
                scatter(ax, Xe.y_toe_begin, Xe.z_toe_begin, 42, c,'o','filled','MarkerEdgeColor','k');
                scatter(ax, Xe.y_toe_land,  Xe.z_toe_land,  42, c,'s','filled','MarkerEdgeColor','k');
                scatter(ax, 0, Xe.z_toe_cross, 62, c,'d','filled','MarkerEdgeColor','k');
            end
        end
        if showHeel
            h2 = plot(ax, A.yHeel, A.zHeel, ls, 'Color', c, 'LineWidth', 1.0); if isempty(hh), hh = h2; end  % heel = thin
            if showMom
                scatter(ax, Xe.y_heel_begin, Xe.z_heel_begin, 32, c,'o','MarkerEdgeColor','k');
                scatter(ax, Xe.y_heel_land,  Xe.z_heel_land,  32, c,'s','MarkerEdgeColor','k');
                scatter(ax, 0, Xe.z_heel_cross, 42, c,'d','MarkerEdgeColor','k');
            end
        end
        if ~isempty(hh) && ~ismember(Xe.terrain, legT), legT{end+1}=Xe.terrain; legH(end+1)=hh; end %#ok<AGROW>
    end
    % moment-marker key (black proxies), shown when the markers are on
    if showMom
        legH(end+1) = plot(ax,nan,nan,'o','MarkerFaceColor','k','MarkerEdgeColor','k','MarkerSize',6,'LineStyle','none'); legT{end+1}='begin-ZVP'; %#ok<AGROW>
        legH(end+1) = plot(ax,nan,nan,'s','MarkerFaceColor','k','MarkerEdgeColor','k','MarkerSize',7,'LineStyle','none'); legT{end+1}='land-ZVP';  %#ok<AGROW>
        legH(end+1) = plot(ax,nan,nan,'d','MarkerFaceColor','k','MarkerEdgeColor','k','MarkerSize',7,'LineStyle','none'); legT{end+1}='z @ y=0';   %#ok<AGROW>
    end
    grid(ax,'on'); box(ax,'on'); ax.FontName = S.fn; ax.XLimMode='auto'; ax.YLimMode='auto';
    xlabel(ax,'y - walking distance from obstacle centre (mm)','FontWeight','bold','FontName',S.fn);
    ylabel(ax,'z - height (mm)','FontWeight','bold','FontName',S.fn);
    title(ax,'Crossing arcs   (Lead solid / Trail dashed; toe thick / heel thin)', ...
          'FontWeight','bold','FontName',S.fn,'Interpreter','none','FontSize',11);
    if ~isempty(legH), legend(ax, legH, legT, 'Location','northeast','Interpreter','none','FontSize',9); else, legend(ax,'off'); end
end

function savePNGarc(hF)
    S = guidata(hF);
    pngFile = fullfile(S.base, sprintf('CrossingArcs_Test%d.png', S.tn));
    exportgraphics(hF, pngFile, 'Resolution', 200);
    fprintf('PNG saved: %s\n', pngFile);
end

function [h_mm, w_mm] = obstacleGeom(terrain, heights_mm)
% 'W{w}_H{h}' (or legacy 'HeightH_DepthD') -> obstacle height and width.
%   height = heights_mm(h)   (the 3 heights passed in, in mm)
%   width  = W1 = 50 mm, W2 = 150 mm
    H = str2double(regexp(terrain,'H(?:eight)?(\d)','tokens','once'));   % H1/H2/H3 or Height1..
    W = str2double(regexp(terrain,'(?:W|Depth)(\d)','tokens','once'));   % W1/W2 or Depth1/Depth2
    if isnan(H) || H < 1 || H > numel(heights_mm), H = 1; end
    h_mm = heights_mm(H);
    wtab = [50 150];
    if isnan(W) || W < 1 || W > 2, w_mm = 50; else, w_mm = wtab(W); end
end

function drawGroupedN(ax, cats, seriesCell, names, colors, ylab, ttl, fn)
% Grouped bars: one bar-series per seriesCell entry (a 1xnCats cell of value
% arrays), with mean+/-SD error bars.
    hold(ax,'on'); nC = numel(cats); nS = numel(seriesCell);
    M = nan(nC,nS); E = nan(nC,nS);
    for s = 1:nS
        mm = cellfun(@(x) mean(x,'omitnan'), seriesCell{s});  M(:,s) = mm(:);
        ss = cellfun(@(x) std(x,0,'omitnan'), seriesCell{s});  E(:,s) = ss(:);
    end
    b = bar(ax, 1:nC, M, 'grouped');
    for s = 1:nS, if s <= numel(colors), b(s).FaceColor = colors{s}; end, end
    for s = 1:nS, errorbar(ax, b(s).XEndPoints, M(:,s)', E(:,s)', 'k', 'LineStyle','none','CapSize',3); end
    set(ax,'XTick',1:nC,'XTickLabel',cats,'TickLabelInterpreter','none','FontName',fn); xtickangle(ax,22);
    ylabel(ax, ylab, 'FontWeight','bold','FontName',fn);
    title(ax, ttl, 'FontName',fn,'FontWeight','bold'); grid(ax,'on'); box(ax,'on');
    legend(ax, names, 'Location','best','FontSize',8);
end

function m = terrainColors(obsTerr)
% Map from terrain name -> RGB (containers.Map).
    if exist('turbo','file'), C = turbo(numel(obsTerr)); else, C = lines(numel(obsTerr)); end
    m = containers.Map('KeyType','char','ValueType','any');
    for i = 1:numel(obsTerr), m(obsTerr{i}) = C(i,:); end
end

function drawGrouped(ax, cats, gL, gR, ylab, ttl, fn)
    nC = numel(cats);
    mL = cellfun(@(x) mean(x,'omitnan'), gL);  sL = cellfun(@(x) std(x,0,'omitnan'), gL);
    mR = cellfun(@(x) mean(x,'omitnan'), gR);  sR = cellfun(@(x) std(x,0,'omitnan'), gR);
    M = [mL(:) mR(:)];
    b = bar(ax, 1:nC, M, 'grouped');
    b(1).FaceColor = [0.20 0.45 0.80];  b(2).FaceColor = [0.85 0.45 0.20];
    xe1 = b(1).XEndPoints;  xe2 = b(2).XEndPoints;
    errorbar(ax, xe1, mL(:)', sL(:)', 'k', 'LineStyle','none','CapSize',4);
    errorbar(ax, xe2, mR(:)', sR(:)', 'k', 'LineStyle','none','CapSize',4);
    set(ax,'XTick',1:nC,'XTickLabel',cats,'FontName',fn,'TickLabelInterpreter','none'); xtickangle(ax,22);
    ylabel(ax, ylab, 'FontWeight','bold','FontName',fn);
    title(ax, ttl, 'Interpreter','none','FontName',fn,'FontWeight','bold');
    legend(ax, {'Leading','Trailing'}, 'Location','best','FontSize',8);
end
