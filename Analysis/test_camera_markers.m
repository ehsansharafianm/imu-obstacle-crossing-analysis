clc; clear; close all;
addpath(fileparts(mfilename('fullpath')));

%% ========================================================================
%% TEST - WorldViz PPT camera markers: trajectory viewers
%% ========================================================================
% Quick system-check (NOT a numbered pipeline step). Reads the PPT tracking log
% CSV from Data/Camera/Test N/ and opens three viewers, each with a checkbox
% toggle per marker and a Line/Scatter/Both style selector:
%   1) 3D trajectory (plot3), drawn so Y is vertical (up)
%   2) positions vs time (X/Y/Z per marker)
%   3) vertical (Y) vs horizontal (XZ-plane) displacement - a 2D side view
%
% CSV format (long/tidy, one row per marker per timestamp):
%   Timestamp, Marker_ID, VRPN_Index, X, Y, Z
% Convention: Y = vertical (up), positions in metres (WorldViz PPT default).

%% ---- input ----
subj_raw = input('  Input Test Number: ', 's');
if isempty(subj_raw), tn = 1; else, tn = str2double(subj_raw); end

%% ---- appearance ----
FONT_NAME   = 'Arial';
LINE_WIDTH  = 1.6;
DOT_SIZE    = 7;                 % start/end markers
FIGURE_POS  = [80 80 1320 780];

%% ---- locate + read the CSV ----
root   = fileparts(fileparts(mfilename('fullpath')));         % project root
camDir = fullfile(root,'Data','Camera',['Test ' num2str(tn)]);
if ~isfolder(camDir), error('Camera folder not found: %s', camDir); end
f = dir(fullfile(camDir,'*.csv'));
if isempty(f), error('No CSV found in %s', camDir); end
csvFile = fullfile(camDir, f(1).name);
fprintf('Reading: %s\n', csvFile);

T  = readtable(csvFile);
vn = T.Properties.VariableNames;
ti = colIndex(vn,'Timestamp',1);
ii = colIndex(vn,'Marker_ID',2);
xi = colIndex(vn,'X',4);  yi = colIndex(vn,'Y',5);  zi = colIndex(vn,'Z',6);
tCol  = T{:,ti};  idCol = T{:,ii};
xCol  = T{:,xi};  yCol  = T{:,yi};  zCol = T{:,zi};

%% ---- split into one trajectory per marker (time-ordered) ----
ids = sort(unique(idCol));
nM  = numel(ids);
fprintf('Found %d markers: %s\n', nM, mat2str(ids(:).'));
M = struct('id',{},'t',{},'xyz',{},'moving',{});
for k = 1:nM
    sel = idCol == ids(k);
    tt  = tCol(sel);
    P   = [xCol(sel), yCol(sel), zCol(sel)];
    [tt, ord] = sort(tt);  P = P(ord,:);
    rng = max(P,[],1) - min(P,[],1);
    M(k).id     = ids(k);
    M(k).t      = tt;
    M(k).xyz    = P;
    M(k).moving = max(rng) > 1e-3;      % flagged only (all are still plotted)
    fprintf('  Marker %2d: %5d frames | range X[% .2f % .2f] Y[% .2f % .2f] Z[% .2f % .2f]%s\n', ...
        ids(k), size(P,1), min(P(:,1)),max(P(:,1)), min(P(:,2)),max(P(:,2)), ...
        min(P(:,3)),max(P(:,3)), ternary(M(k).moving,'',rep_static()));
end

%% ---- build the 3D figure ----
if exist('turbo','file'), colors = turbo(nM); else, colors = hsv(nM); end
hFig = figure('Color','w','Position',FIGURE_POS, ...
    'Name',sprintf('PPT camera markers 3D | Test %d', tn));
ax = axes(hFig,'Position',[0.30 0.09 0.66 0.83]); hold(ax,'on'); grid(ax,'on'); box(ax,'on');

hLine = gobjects(nM,1); hStart = gobjects(nM,1); hEnd = gobjects(nM,1); hScat = gobjects(nM,1);
% Plotted as (X, Z, Y): data Y (vertical) is drawn on the plot's Z axis, which is
% MATLAB's screen-up direction - so Y shows as vertical. Axis labels match the
% data each plot axis carries (plot-z shows Y). Line + scatter are both pre-drawn;
% the Style selector toggles which is shown (scatter = one dot per sample, so
% dropouts appear as missing dots rather than a bridged line).
for k = 1:nM
    P = M(k).xyz;
    hLine(k)  = plot3(ax, P(:,1), P(:,3), P(:,2), '-', 'Color', colors(k,:), 'LineWidth', LINE_WIDTH);
    hScat(k)  = scatter3(ax, P(:,1), P(:,3), P(:,2), 10, colors(k,:), 'filled');
    hStart(k) = plot3(ax, P(1,1),  P(1,3),  P(1,2),  'o', 'Color', colors(k,:), ...
                      'MarkerFaceColor', colors(k,:), 'MarkerSize', DOT_SIZE);
    hEnd(k)   = plot3(ax, P(end,1),P(end,3),P(end,2),'s', 'Color', colors(k,:), ...
                      'MarkerFaceColor', 'w', 'MarkerSize', DOT_SIZE+1, 'LineWidth', 1.3);
end
axis(ax,'equal'); view(ax,3); rotate3d(ax,'on');
ax.FontName = FONT_NAME; ax.FontWeight = 'bold';
xlabel(ax,'X (m)','FontWeight','bold'); ylabel(ax,'Z (m)','FontWeight','bold'); zlabel(ax,'Y (m)  - vertical','FontWeight','bold');
title(ax, sprintf('PPT marker trajectories | Test %d   (o = start, \\Box = end)', tn), ...
      'FontName',FONT_NAME,'FontWeight','bold','Interpreter','tex');

%% ---- controls (style selector + per-marker toggle) ----
LX = 0.02;  LW = 0.24;
uicontrol(hFig,'Style','text','Units','normalized','Position',[LX 0.945 0.07 0.03], ...
    'String','Style:','BackgroundColor','w','FontName',FONT_NAME,'FontWeight','bold','HorizontalAlignment','left');
styleDD = uicontrol(hFig,'Style','popupmenu','Units','normalized','Position',[LX+0.075 0.947 0.155 0.03], ...
    'String',{'Line','Scatter','Both'},'Value',3,'FontName',FONT_NAME,'Callback',@(~,~) updateVis(hFig));
uicontrol(hFig,'Style','pushbutton','Units','normalized','Position',[LX 0.90 0.11 0.04], ...
    'String','Select all','FontName',FONT_NAME,'Callback',@(~,~) setAll(hFig,true));
uicontrol(hFig,'Style','pushbutton','Units','normalized','Position',[LX+0.12 0.90 0.11 0.04], ...
    'String','Clear all','FontName',FONT_NAME,'Callback',@(~,~) setAll(hFig,false));
uicontrol(hFig,'Style','pushbutton','Units','normalized','Position',[LX 0.855 0.23 0.04], ...
    'String','Save PNG','FontName',FONT_NAME,'Callback',@(~,~) savePNG(hFig));

pnl = uipanel(hFig,'Title','Markers','Units','normalized','Position',[LX 0.09 LW 0.75], ...
    'BackgroundColor','w','FontName',FONT_NAME,'FontSize',11,'FontWeight','bold');
rh = 1/max(nM,1);  cb = gobjects(nM,1);
for k = 1:nM
    cb(k) = uicontrol(pnl,'Style','checkbox','Units','normalized', ...
        'Position',[0.06 1-k*rh 0.9 rh*0.9], 'String',sprintf('Marker %d', M(k).id), ...
        'Value',1, 'ForegroundColor',[0 0 0], 'BackgroundColor','w', ...
        'FontName',FONT_NAME,'FontSize',11,'Callback',@(~,~) updateVis(hFig));
end

S = struct('cb',cb,'hLine',hLine,'hStart',hStart,'hEnd',hEnd,'hScat',hScat,'ax',ax, ...
           'styleDD',styleDD,'styleItems',{{'Line','Scatter','Both'}}, ...
           'M',{M},'n',nM,'tn',tn,'camDir',camDir,'FONT_NAME',FONT_NAME);
guidata(hFig, S);
updateVis(hFig);
fprintf('Ready: %d marker trajectories. Rotate with the mouse; toggle markers on the left.\n', nM);

%% ---- second view: positions vs time (X/Y/Z per marker, all toggleable) ----
timeViewer(M, colors, tn, camDir, FONT_NAME);

%% ---- third view: vertical (Y) vs horizontal (XZ) displacement, 2D ----
dispViewer(M, colors, tn, camDir, FONT_NAME);

%% ========================================================================
%  LOCAL FUNCTIONS
%% ========================================================================
function updateVis(hFig)
    S = guidata(hFig);
    style   = S.styleItems{S.styleDD.Value};
    useLine = any(strcmp(style,{'Line','Both'}));
    useScat = any(strcmp(style,{'Scatter','Both'}));
    legH = [];  legN = {};
    for k = 1:S.n
        on = S.cb(k).Value == 1;
        set(S.hLine(k),  'Visible', tf2vis(on && useLine));
        set(S.hStart(k), 'Visible', tf2vis(on && useLine));   % start/end dots ride with the line
        set(S.hEnd(k),   'Visible', tf2vis(on && useLine));
        set(S.hScat(k),  'Visible', tf2vis(on && useScat));
        if on
            if useLine, legH(end+1) = S.hLine(k); else, legH(end+1) = S.hScat(k); end %#ok<AGROW>
            legN{end+1} = sprintf('Marker %d', S.M(k).id); %#ok<AGROW>
        end
    end
    if ~isempty(legH)
        legend(S.ax, legH, legN, 'Location','eastoutside','FontName',S.FONT_NAME);
    else
        legend(S.ax, 'off');
    end
end

function setAll(hFig, val)
    S = guidata(hFig);
    for k = 1:S.n, S.cb(k).Value = val; end
    updateVis(hFig);
end

function savePNG(hFig)
    S = guidata(hFig);
    pngFile = fullfile(S.camDir, sprintf('CameraMarkers3D_Test%d.png', S.tn));
    exportgraphics(hFig, pngFile, 'Resolution', 300);
    fprintf('PNG saved: %s\n', pngFile);
end

%% ----- second viewer: positions vs time -----
function timeViewer(M, colors, tn, camDir, fontName)
% Per-marker X/Y/Z position vs time. Toggle which markers AND which axes to show.
    nM = numel(M);
    axNames = {'X','Y','Z'};  axMarkers = {'o','s','^'};
    hF = figure('Color','w','Position',[110 90 1320 780], ...
        'Name',sprintf('PPT markers vs time | Test %d', tn));
    ax = axes(hF,'Position',[0.30 0.11 0.66 0.80]); hold(ax,'on');
    LX = 0.02;  LW = 0.24;

    % axis (component) checkboxes
    uicontrol(hF,'Style','text','Units','normalized','Position',[LX 0.95 0.08 0.03], ...
        'String','Axes:','BackgroundColor','w','FontName',fontName,'FontWeight','bold','HorizontalAlignment','left');
    axCb = gobjects(3,1);
    for a = 1:3
        axCb(a) = uicontrol(hF,'Style','checkbox','Units','normalized', ...
            'Position',[LX+0.075+(a-1)*0.05, 0.95, 0.05, 0.03], 'String',axNames{a}, ...
            'Value',1,'BackgroundColor','w','FontName',fontName,'FontWeight','bold', ...
            'Callback',@(~,~) updateTV(hF));
    end

    % plot style
    uicontrol(hF,'Style','text','Units','normalized','Position',[LX 0.905 0.07 0.03], ...
        'String','Style:','BackgroundColor','w','FontName',fontName,'FontWeight','bold','HorizontalAlignment','left');
    styleDD = uicontrol(hF,'Style','popupmenu','Units','normalized','Position',[LX+0.075 0.907 0.155 0.03], ...
        'String',{'Line','Scatter','Both'},'Value',3,'FontName',fontName,'Callback',@(~,~) updateTV(hF));

    uicontrol(hF,'Style','pushbutton','Units','normalized','Position',[LX 0.86 0.11 0.04], ...
        'String','Select all','FontName',fontName,'Callback',@(~,~) setAllTV(hF,true));
    uicontrol(hF,'Style','pushbutton','Units','normalized','Position',[LX+0.12 0.86 0.11 0.04], ...
        'String','Clear all','FontName',fontName,'Callback',@(~,~) setAllTV(hF,false));
    uicontrol(hF,'Style','pushbutton','Units','normalized','Position',[LX 0.815 0.23 0.04], ...
        'String','Save PNG','FontName',fontName,'Callback',@(~,~) savePNGtv(hF));

    pnl = uipanel(hF,'Title','Markers','Units','normalized','Position',[LX 0.09 LW 0.71], ...
        'BackgroundColor','w','FontName',fontName,'FontSize',11,'FontWeight','bold');
    rh = 1/max(nM,1);  cb = gobjects(nM,1);
    for k = 1:nM
        cb(k) = uicontrol(pnl,'Style','checkbox','Units','normalized', ...
            'Position',[0.06 1-k*rh 0.9 rh*0.9], 'String',sprintf('Marker %d', M(k).id), ...
            'Value',1,'ForegroundColor',[0 0 0],'BackgroundColor','w', ...
            'FontName',fontName,'FontSize',11,'Callback',@(~,~) updateTV(hF));
    end

    S = struct('cb',cb,'axCb',axCb,'ax',ax,'M',{M},'n',nM,'color',colors, ...
               'axNames',{axNames},'axMarkers',{axMarkers},'styleDD',styleDD, ...
               'styleItems',{{'Line','Scatter','Both'}},'tn',tn,'camDir',camDir,'fontName',fontName);
    guidata(hF, S);  updateTV(hF);
end

function updateTV(hF)
    S = guidata(hF);  ax = S.ax;  cla(ax);  hold(ax,'on');
    selAx   = find(arrayfun(@(h) h.Value==1, S.axCb));
    style   = S.styleItems{S.styleDD.Value};
    useLine = any(strcmp(style,{'Line','Both'}));
    useScat = any(strcmp(style,{'Scatter','Both'}));
    multiA  = numel(selAx) > 1;
    legH = [];  legN = {};
    for k = 1:S.n
        if S.cb(k).Value ~= 1, continue; end
        t = S.M(k).t;  P = S.M(k).xyz;  c = S.color(k,:);
        for a = selAx(:)'
            y = P(:,a);  amk = S.axMarkers{a};  h = [];
            if useLine
                if multiA
                    step = max(1, round(numel(t)/30));
                    h = plot(ax, t, y, '-', 'Color', c, 'LineWidth', 1.5, ...
                             'Marker', amk, 'MarkerIndices', 1:step:numel(t), 'MarkerSize', 5);
                else
                    h = plot(ax, t, y, '-', 'Color', c, 'LineWidth', 1.5);
                end
            end
            if useScat
                hs = scatter(ax, t, y, 12, c, amk, 'filled');   % one dot per sample
                if isempty(h), h = hs; end
            end
            legH(end+1) = h; %#ok<AGROW>
            if multiA, legN{end+1} = sprintf('Marker %d - %s', S.M(k).id, S.axNames{a}); %#ok<AGROW>
            else,      legN{end+1} = sprintf('Marker %d', S.M(k).id); end %#ok<AGROW>
        end
    end
    grid(ax,'on'); box(ax,'on'); ax.FontName = S.fontName; ax.FontWeight = 'bold';
    xlabel(ax,'Time (s)','FontWeight','bold','FontSize',13);
    if numel(selAx) == 1, yl = sprintf('%s position (m)', S.axNames{selAx}); else, yl = 'Position (m)'; end
    ylabel(ax, yl, 'FontWeight','bold','FontSize',13);
    ttl = sprintf('PPT marker positions vs time | Test %d', S.tn);
    if ~isempty(selAx), ttl = [ttl '   (' strjoin(S.axNames(selAx), ', ') ')']; end
    title(ax, ttl, 'FontName',S.fontName,'FontWeight','bold','Interpreter','none');
    if ~isempty(legH)
        legend(ax, legH, legN, 'Location','eastoutside','FontName',S.fontName,'FontSize',9);
    else
        legend(ax,'off');
    end
end

function setAllTV(hF, val)
    S = guidata(hF);
    for k = 1:S.n, S.cb(k).Value = val; end
    updateTV(hF);
end

function savePNGtv(hF)
    S = guidata(hF);
    pngFile = fullfile(S.camDir, sprintf('CameraMarkers_Time_Test%d.png', S.tn));
    exportgraphics(hF, pngFile, 'Resolution', 300);
    fprintf('PNG saved: %s\n', pngFile);
end

%% ----- third viewer: vertical (Y) vs horizontal (XZ) displacement (2D side view) -----
function dispViewer(M, colors, tn, camDir, fontName)
% 2D elevation view: vertical Y vs horizontal displacement in the XZ plane
% (d = sqrt((X-X0)^2 + (Z-Z0)^2) from each marker's own start). Toggle per marker.
    nM = numel(M);
    hF = figure('Color','w','Position',[130 70 1320 780], ...
        'Name',sprintf('PPT markers: vertical vs horizontal displacement | Test %d', tn));
    ax = axes(hF,'Position',[0.30 0.11 0.66 0.80]); hold(ax,'on');
    LX = 0.02;  LW = 0.24;

    uicontrol(hF,'Style','text','Units','normalized','Position',[LX 0.945 0.07 0.03], ...
        'String','Style:','BackgroundColor','w','FontName',fontName,'FontWeight','bold','HorizontalAlignment','left');
    styleDD = uicontrol(hF,'Style','popupmenu','Units','normalized','Position',[LX+0.075 0.947 0.155 0.03], ...
        'String',{'Line','Scatter','Both'},'Value',3,'FontName',fontName,'Callback',@(~,~) updateDV(hF));
    uicontrol(hF,'Style','pushbutton','Units','normalized','Position',[LX 0.90 0.11 0.04], ...
        'String','Select all','FontName',fontName,'Callback',@(~,~) setAllDV(hF,true));
    uicontrol(hF,'Style','pushbutton','Units','normalized','Position',[LX+0.12 0.90 0.11 0.04], ...
        'String','Clear all','FontName',fontName,'Callback',@(~,~) setAllDV(hF,false));
    uicontrol(hF,'Style','pushbutton','Units','normalized','Position',[LX 0.855 0.23 0.04], ...
        'String','Save PNG','FontName',fontName,'Callback',@(~,~) savePNGdv(hF));

    pnl = uipanel(hF,'Title','Markers','Units','normalized','Position',[LX 0.09 LW 0.75], ...
        'BackgroundColor','w','FontName',fontName,'FontSize',11,'FontWeight','bold');
    rh = 1/max(nM,1);  cb = gobjects(nM,1);
    for k = 1:nM
        cb(k) = uicontrol(pnl,'Style','checkbox','Units','normalized', ...
            'Position',[0.06 1-k*rh 0.9 rh*0.9], 'String',sprintf('Marker %d', M(k).id), ...
            'Value',1,'ForegroundColor',[0 0 0],'BackgroundColor','w', ...
            'FontName',fontName,'FontSize',11,'Callback',@(~,~) updateDV(hF));
    end

    S = struct('cb',cb,'ax',ax,'M',{M},'n',nM,'color',colors,'styleDD',styleDD, ...
               'styleItems',{{'Line','Scatter','Both'}},'tn',tn,'camDir',camDir,'fontName',fontName);
    guidata(hF, S);  updateDV(hF);
end

function updateDV(hF)
    S = guidata(hF);  ax = S.ax;  cla(ax);  hold(ax,'on');
    style   = S.styleItems{S.styleDD.Value};
    useLine = any(strcmp(style,{'Line','Both'}));
    useScat = any(strcmp(style,{'Scatter','Both'}));
    legH = [];  legN = {};
    for k = 1:S.n
        if S.cb(k).Value ~= 1, continue; end
        P = S.M(k).xyz;  c = S.color(k,:);
        d = sqrt((P(:,1)-P(1,1)).^2 + (P(:,3)-P(1,3)).^2);   % horizontal (XZ) displacement from start
        y = P(:,2);                                          % vertical
        h = [];
        if useLine, h = plot(ax, d, y, '-', 'Color', c, 'LineWidth', 1.5); end
        if useScat, hs = scatter(ax, d, y, 12, c, 'filled'); if isempty(h), h = hs; end; end
        legH(end+1) = h; %#ok<AGROW>
        legN{end+1} = sprintf('Marker %d', S.M(k).id); %#ok<AGROW>
    end
    grid(ax,'on'); box(ax,'on'); ax.FontName = S.fontName; ax.FontWeight = 'bold';
    xlabel(ax,'Horizontal displacement in XZ (m)','FontWeight','bold','FontSize',13);
    ylabel(ax,'Vertical  Y (m)','FontWeight','bold','FontSize',13);
    title(ax, sprintf('Vertical vs horizontal displacement | Test %d', S.tn), ...
          'FontName',S.fontName,'FontWeight','bold','Interpreter','none');
    if ~isempty(legH)
        legend(ax, legH, legN, 'Location','eastoutside','FontName',S.fontName,'FontSize',9);
    else
        legend(ax,'off');
    end
end

function setAllDV(hF, val)
    S = guidata(hF);
    for k = 1:S.n, S.cb(k).Value = val; end
    updateDV(hF);
end

function savePNGdv(hF)
    S = guidata(hF);
    pngFile = fullfile(S.camDir, sprintf('CameraMarkers_VertDisp_Test%d.png', S.tn));
    exportgraphics(hF, pngFile, 'Resolution', 300);
    fprintf('PNG saved: %s\n', pngFile);
end

function v = tf2vis(tf), if tf, v = 'on'; else, v = 'off'; end, end

function idx = colIndex(vn, name, pos)
% Column index by (case-insensitive) name; fall back to a positional guess.
    idx = find(strcmpi(vn, name), 1);
    if isempty(idx), idx = pos; end
end

function s = rep_static(),  s = '   <-- static';  end
function out = ternary(c, a, b), if c, out = a; else, out = b; end, end
