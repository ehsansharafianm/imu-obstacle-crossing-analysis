clc
clear
close all
addpath(fileparts(mfilename('fullpath')));

%% ========================================================================
%% Dot IMU sanity-check plot  (standalone)
%% ========================================================================
% Reads the 6 Dot IMU CSVs for a test, converts orientation to Euler ZXY,
% and plots them in the same interactive template as step 3 (Z/X/Y angle
% checkboxes, per-IMU toggles, Line/Scatter, Save PNG). Dot only - no Awinda,
% no sync, no joints. Just for eyeballing the raw Dot results.

%% ===================== APPEARANCE SETTINGS =====================
FONT_NAME      = 'Arial';
TITLE_SIZE     = 18;  XLABEL_SIZE = 15;  YLABEL_SIZE = 15;  TICK_SIZE = 12;  LEGEND_SIZE = 10;
BOX_LINE_WIDTH = 1.3;
FIGURE_POS     = [60, 60, 1320, 760];
PLOT_STYLE     = 'Line';      % 'Line' | 'Scatter' | 'Both'
LINE_WIDTH     = 1.6;
SCATTER_SIZE   = 14;
EULER_SEQ      = 'ZYX';       % Euler sequence (X is the last axis here -> smooth, atan2)
EULER_TYPE     = 'frame';     % 'frame' or 'point' (rotation convention)
ANGLE_MARKERS  = {'o','s','^'};        % markers for [Z X Y] when >1 angle shown
DEFAULT_ANGLES = (EULER_SEQ == 'X');   % show the X channel on first open
START_ALL_ON   = true;                 % start with every IMU ticked
REMOVE_OFFSET  = true;                 % zero each angle at the start
OFFSET_SAMPLES = 10;                   % samples averaged for the offset
CB_FONT_SIZE   = 11;
RATE_DOT       = 60;                   % Hz
PACKET_MODULUS = 1e6;                  % strip terrain packet offset (0 = off)
EXPORT_RESOLUTION = 300;

%% ===================== INPUT =====================
tn = input('  Input Test Number: ');
dataDir = fullfile('..','Data','Dot IMUs', ['Test ' num2str(tn)]);
if ~isfolder(dataDir), error('Not found: %s', dataDir); end
figDir = fullfile('..','Results','Parameters Output', ['Test ' num2str(tn)]);

defs = {'IMU1','Left Foot'; 'IMU2','Right Foot'; 'IMU3','Left Thigh'; ...
        'IMU4','Right Thigh'; 'IMU5','Left Shank'; 'IMU6','Right Shank'};

%% ===================== READ + EULER =====================
labels = {}; tCell = {}; eCell = {};
for b = 1:size(defs,1)
    fp = findFile(dataDir, [defs{b,1} '_*.csv']);
    if isempty(fp), warning('Missing %s', defs{b,1}); continue; end
    [cols, M] = readIMUFile(fp);
    pkt = M(:, find(strcmpi(cols,'PacketCounter'),1));
    if PACKET_MODULUS > 0, pkt = mod(pkt, PACKET_MODULUS); end
    E = quat2euler(getQuatCols(cols, M), EULER_SEQ, EULER_TYPE);
    if REMOVE_OFFSET
        k = min(OFFSET_SAMPLES, size(E,1));
        E = E - mean(E(1:k,:), 1);                              % zero each angle at the start
    end
    tCell{end+1} = (pkt - pkt(1)) / RATE_DOT;                   %#ok<SAGROW>
    eCell{end+1} = E;                                           %#ok<SAGROW>
    labels{end+1} = defs{b,2};                                 %#ok<SAGROW>
    fprintf('  %-12s <- %s  (%d frames)\n', defs{b,2}, defs{b,1}, size(M,1));
end
nItem = numel(labels);
if nItem == 0, error('No Dot IMU files found in %s', dataDir); end
if exist('turbo','file'), colorMat = turbo(nItem); else, colorMat = hsv(nItem); end
angShort = num2cell(EULER_SEQ);                                   % e.g. {'Z','X','Y'}
angFull  = cellfun(@(c) sprintf('Euler %s (deg)', c), angShort, 'UniformOutput', false);
titleStr = sprintf('Dot IMUs  |  Test %d  (Euler %s)', tn, EULER_SEQ);

%% ===================== FIGURE =====================
hFig = figure('Position', FIGURE_POS, 'Color', 'w', 'Name', titleStr);
ax = axes(hFig, 'Position', [0.42 0.13 0.55 0.76]);
LX = 0.02;  LW = 0.34;

uicontrol(hFig,'Style','text','Units','normalized','Position',[LX 0.95 0.09 0.03], ...
    'String','Angles:','BackgroundColor','w','FontName',FONT_NAME,'FontSize',11, ...
    'FontWeight','bold','HorizontalAlignment','left');
angCb = gobjects(3,1);
for a = 1:3
    angCb(a) = uicontrol(hFig,'Style','checkbox','Units','normalized', ...
        'Position',[LX+0.10+(a-1)*0.075, 0.95, 0.07, 0.03], 'String',angShort{a}, ...
        'Value',DEFAULT_ANGLES(a),'BackgroundColor','w','FontName',FONT_NAME, ...
        'FontSize',11,'FontWeight','bold','Callback',@(~,~) updatePlot(hFig));
end

uicontrol(hFig,'Style','text','Units','normalized','Position',[LX 0.905 0.12 0.035], ...
    'String','Plot style:','BackgroundColor','w','FontName',FONT_NAME,'FontSize',11, ...
    'FontWeight','bold','HorizontalAlignment','left');
styleItems = {'Line','Scatter','Both'};
styleDD = uicontrol(hFig,'Style','popupmenu','Units','normalized', ...
    'Position',[LX+0.12 0.907 0.20 0.04],'String',styleItems, ...
    'Value',find(strcmpi(styleItems,PLOT_STYLE),1), ...
    'FontName',FONT_NAME,'FontSize',11,'Callback',@(~,~) updatePlot(hFig));

uicontrol(hFig,'Style','pushbutton','Units','normalized','Position',[LX 0.858 0.105 0.04], ...
    'String','Select all','FontName',FONT_NAME,'FontSize',10,'Callback',@(~,~) setAll(hFig,true));
uicontrol(hFig,'Style','pushbutton','Units','normalized','Position',[LX+0.115 0.858 0.105 0.04], ...
    'String','Clear all','FontName',FONT_NAME,'FontSize',10,'Callback',@(~,~) setAll(hFig,false));
uicontrol(hFig,'Style','pushbutton','Units','normalized','Position',[LX+0.23 0.858 0.105 0.04], ...
    'String','Save PNG','FontName',FONT_NAME,'FontSize',10,'Callback',@(~,~) savePNG(hFig));

pnl = uipanel(hFig,'Title','Dot IMUs','Units','normalized','Position',[LX 0.04 LW 0.80], ...
    'BackgroundColor','w','FontName',FONT_NAME,'FontSize',11,'FontWeight','bold');
rh = 1/nItem;  cb = gobjects(nItem,1);
for i = 1:nItem
    cb(i) = uicontrol(pnl,'Style','checkbox','Units','normalized', ...
        'Position',[0.03 1-i*rh 0.95 rh*0.9],'String',labels{i},'Value',START_ALL_ON, ...
        'BackgroundColor','w','FontName',FONT_NAME,'FontSize',CB_FONT_SIZE, ...
        'Callback',@(~,~) updatePlot(hFig));
end

S = struct('ax',ax,'cb',cb,'angCb',angCb,'time',{tCell},'euler',{eCell}, ...
           'label',{labels},'color',colorMat,'n',nItem,'styleDD',styleDD, ...
           'styleItems',{styleItems},'angFull',{angFull},'angShort',{angShort}, ...
           'angMarkers',{ANGLE_MARKERS},'titleStr',titleStr,'LEGEND_ON',true, ...
           'LEGEND_SIZE',LEGEND_SIZE,'FONT_NAME',FONT_NAME,'TITLE_SIZE',TITLE_SIZE, ...
           'XLABEL_SIZE',XLABEL_SIZE,'YLABEL_SIZE',YLABEL_SIZE,'TICK_SIZE',TICK_SIZE, ...
           'BOX_LINE_WIDTH',BOX_LINE_WIDTH,'LINE_WIDTH',LINE_WIDTH,'SCATTER_SIZE',SCATTER_SIZE, ...
           'figDir',figDir,'tn',tn,'EXPORT_RESOLUTION',EXPORT_RESOLUTION);
guidata(hFig, S);
updatePlot(hFig);
fprintf('Ready: %d Dot IMUs for Test %d.\n', nItem, tn);

%% ========================================================================
%  LOCAL FUNCTIONS
%% ========================================================================
function updatePlot(hFig)
    S = guidata(hFig);
    selAng = find(arrayfun(@(h) h.Value==1, S.angCb));   % subset of [Z X Y]
    style  = S.styleItems{S.styleDD.Value};
    useLine = any(strcmp(style,{'Line','Both'}));
    useScat = any(strcmp(style,{'Scatter','Both'}));
    multiA  = numel(selAng) > 1;
    cla(S.ax); hold(S.ax,'on'); legH = []; legN = {};
    for i = 1:S.n
        if S.cb(i).Value ~= 1, continue; end
        t = S.time{i}; col = S.color(i,:);
        for a = selAng(:)'
            y = S.euler{i}(:,a);
            mk = 'none'; if multiA, mk = S.angMarkers{a}; end
            h = [];
            if useLine
                if strcmp(mk,'none')
                    h = plot(S.ax, t, y, '-', 'Color', col, 'LineWidth', S.LINE_WIDTH);
                else
                    step = max(1, round(numel(t)/25));
                    h = plot(S.ax, t, y, '-', 'Color', col, 'LineWidth', S.LINE_WIDTH, ...
                             'Marker', mk, 'MarkerIndices', 1:step:numel(t), 'MarkerSize', 5);
                end
            end
            if useScat
                smk = 'o'; if multiA, smk = S.angMarkers{a}; end
                hs = scatter(S.ax, t, y, S.SCATTER_SIZE, col, smk, 'filled');
                if isempty(h), h = hs; end
            end
            if multiA, name = [S.label{i} ' - ' S.angShort{a}]; else, name = S.label{i}; end
            legH(end+1) = h; legN{end+1} = name; %#ok<AGROW>
        end
    end
    hold(S.ax,'off'); grid(S.ax,'on'); box(S.ax,'on');
    S.ax.FontName=S.FONT_NAME; S.ax.FontSize=S.TICK_SIZE; S.ax.FontWeight='bold';
    S.ax.LineWidth=S.BOX_LINE_WIDTH;
    if numel(selAng) == 1, yl = S.angFull{selAng}; else, yl = 'Euler angle (deg)'; end
    xlabel(S.ax,'Time (s)','FontSize',S.XLABEL_SIZE,'FontWeight','bold','FontName',S.FONT_NAME);
    ylabel(S.ax,yl,'FontSize',S.YLABEL_SIZE,'FontWeight','bold','FontName',S.FONT_NAME,'Interpreter','none');
    angTxt = strjoin(S.angShort(selAng), ',');
    title(S.ax,[S.titleStr '   -   Euler ' angTxt],'FontSize',S.TITLE_SIZE,'FontWeight','bold', ...
          'FontName',S.FONT_NAME,'Interpreter','none');
    if S.LEGEND_ON && ~isempty(legH)
        legend(S.ax, legH, legN, 'Location','eastoutside', ...
            'FontSize',S.LEGEND_SIZE,'FontName',S.FONT_NAME,'Interpreter','none');
    else
        legend(S.ax,'off');
    end
end

function setAll(hFig, val)
    S = guidata(hFig);
    for i = 1:S.n, S.cb(i).Value = val; end
    updatePlot(hFig);
end

function savePNG(hFig)
    S = guidata(hFig);
    if ~exist(S.figDir,'dir'), mkdir(S.figDir); end
    pngFile = fullfile(S.figDir, sprintf('DotIMU_Check_Test%d.png', S.tn));
    exportgraphics(hFig, pngFile, 'Resolution', S.EXPORT_RESOLUTION);
    fprintf('PNG saved: %s\n', pngFile);
end

function fp = findFile(dataDir, pattern)
    d = dir(fullfile(dataDir, pattern));
    if isempty(d), fp = ''; else, fp = fullfile(dataDir, d(1).name); end
end

function [cols, M] = readIMUFile(file)
% Read a Movella Dot .csv: find the 'PacketCounter' header line, comma-delim.
    fid = fopen(file,'r');
    if fid < 0, error('Cannot open %s', file); end
    headerLine = '';
    while true
        line = fgetl(fid);
        if ~ischar(line), fclose(fid); error('No PacketCounter header in %s', file); end
        if contains(line,'PacketCounter'), headerLine = line; break; end
    end
    if contains(headerLine, sprintf('\t')), delim = sprintf('\t'); else, delim = ','; end
    cols = strtrim(strsplit(strtrim(headerLine), delim));
    C = textscan(fid, repmat('%f',1,numel(cols)), 'Delimiter', delim, ...
                 'CollectOutput', true, 'EmptyValue', NaN);
    fclose(fid);
    M = C{1};
end

function Q = getQuatCols(cols, M)
    names = {'Quat_W','Quat_X','Quat_Y','Quat_Z'; 'Quat_q0','Quat_q1','Quat_q2','Quat_q3'};
    for r = 1:size(names,1)
        idx = zeros(1,4); ok = true;
        for k = 1:4
            j = find(strcmpi(cols, names{r,k}), 1);
            if isempty(j), ok = false; break; end
            idx(k) = j;
        end
        if ok, Q = M(:, idx); return; end
    end
    error('Quaternion columns not found.');
end

function E = quat2euler(Q, seq, type)
% Quaternion [w x y z] -> Euler angles (deg) for the given sequence/type.
    if exist('quaternion','class') ~= 8
        error('Needs the quaternion class (Sensor Fusion / Navigation / Robotics Toolbox).');
    end
    E = eulerd(quaternion(Q), seq, type);
end
