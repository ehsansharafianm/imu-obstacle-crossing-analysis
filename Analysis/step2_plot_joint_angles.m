clc
clear all
close all
addpath(fileparts(mfilename('fullpath')));

%% ========================================================================
%% SUBJECT INPUT
%% ========================================================================
subj_raw = input('  Input Test Number: ', 's');
if isempty(subj_raw), subjectNumber = 1; else, subjectNumber = str2double(subj_raw); end

ikDir = fullfile('..', 'Results', 'OpenSim Outputs', ['Test ' num2str(subjectNumber)], 'IKResults');
f = dir(fullfile(ikDir, 'ik_*.mot'));
if isempty(f)
    error('No ik_*.mot found in %s. Run the pipeline first.', ikDir);
end
[~, newest] = max([f.datenum]);                 % most recent IK result
motFile = fullfile(ikDir, f(newest).name);
fprintf('Loading: %s\n', motFile);

%% ========================================================================
%% APPEARANCE SETTINGS — ADJUST HERE
%% ========================================================================
FONT_NAME      = 'Arial';
TITLE_SIZE     = 18;
XLABEL_SIZE    = 15;
YLABEL_SIZE    = 15;
TICK_SIZE      = 12;
LEGEND_SIZE    = 9;
BOX_LINE_WIDTH = 1.3;
GRID_ON        = true;
FIGURE_POS     = [60, 60, 1300, 740];

PLOT_STYLE     = 'Line';     % initial style: 'Line' | 'Scatter' | 'Both'
LINE_WIDTH     = 2.1;      % connecting line width
SCATTER_SIZE   = 16;         % dot size
MARKER         = 'o';        % scatter marker shape

LEGEND_ON      = true;       % show legend of visible joints
START_ALL_ON   = false;      % true: start with every joint ticked; false: use DEFAULT_ON_JOINTS
DEFAULT_ON_JOINTS = {'hip_flexion_r', 'knee_angle_r', 'ankle_angle_r', ...
                     'hip_flexion_l', 'knee_angle_l', 'ankle_angle_l'};  % ticked on first open

% --- Toggle (checkbox) panel ---
CB_COLUMNS        = 2;        % how many columns of checkboxes
CB_FONT_SIZE      = 11;       % checkbox text size
CB_COLOR_BY_CURVE = false;   % true: text matches curve colour | false: use CB_TEXT_COLOR
CB_TEXT_COLOR     = [0 0 0];  % uniform text colour when CB_COLOR_BY_CURVE = false

EXPORT_RESOLUTION = 300;      % DPI for the Save-PNG button

%% ========================================================================
%% READ DATA
%% ========================================================================
[t, data, labels] = readMot(motFile);
nJoints = numel(labels);
subjectLabel = ['Test ' num2str(subjectNumber)];

% Pull the recording date/time from the file name prefix (MT_YYYY-MM-DD_HHhMM)
% for the plot title; keep subjectLabel clean for file names.
dt = regexp(motFile, '(\d{4}-\d{2}-\d{2})_(\d{2})h(\d{2})', 'tokens', 'once');
if isempty(dt)
    titleStr = subjectLabel;
else
    titleStr = sprintf('%s   |   %s   %s:%s', subjectLabel, dt{1}, dt{2}, dt{3});
end

% A distinct colour per joint so each curve keeps its colour when toggled.
if exist('turbo', 'file'), colors = turbo(nJoints); else, colors = hsv(nJoints); end

%% ========================================================================
%% BUILD FIGURE
%% ========================================================================
hFig = figure('Position', FIGURE_POS, 'Color', 'w', ...
    'Name', ['Joint angles  -  ' subjectLabel]);

% ---- Plot axes (right side) ----
ax = axes(hFig, 'Position', [0.42 0.13 0.55 0.76]);
hold(ax, 'on');

% Pre-plot every joint as BOTH a line and a scatter; visibility is toggled.
hLine = gobjects(nJoints, 1);
hScat = gobjects(nJoints, 1);
for i = 1:nJoints
    hLine(i) = plot(ax, t, data(:, i), '-', 'Color', colors(i, :), ...
                    'LineWidth', LINE_WIDTH);
    hScat(i) = scatter(ax, t, data(:, i), SCATTER_SIZE, colors(i, :), ...
                       MARKER, 'filled');
end
applyAxStyle(ax, FONT_NAME, TICK_SIZE, BOX_LINE_WIDTH, GRID_ON);
xlabel(ax, 'Time (s)', 'FontSize', XLABEL_SIZE, 'FontWeight', 'bold', 'FontName', FONT_NAME);
ylabel(ax, 'Angle (deg) / translation (m)', 'FontSize', YLABEL_SIZE, 'FontWeight', 'bold', 'FontName', FONT_NAME);
title(ax, titleStr, 'FontSize', TITLE_SIZE, 'FontWeight', 'bold', 'FontName', FONT_NAME, 'Interpreter', 'none');

% ---- Left control column ----
LX = 0.02;  LW = 0.34;

uicontrol(hFig, 'Style', 'text', 'Units', 'normalized', ...
    'Position', [LX 0.925 0.12 0.04], 'String', 'Plot style:', ...
    'BackgroundColor', 'w', 'FontName', FONT_NAME, 'FontSize', 11, ...
    'FontWeight', 'bold', 'HorizontalAlignment', 'left');

styleItems = {'Line', 'Scatter', 'Both'};
styleDD = uicontrol(hFig, 'Style', 'popupmenu', 'Units', 'normalized', ...
    'Position', [LX+0.12 0.93 0.20 0.045], 'String', styleItems, ...
    'Value', find(strcmpi(styleItems, PLOT_STYLE), 1), ...
    'FontName', FONT_NAME, 'FontSize', 11, ...
    'Callback', @(~,~) updateVis(hFig));

uicontrol(hFig, 'Style', 'pushbutton', 'Units', 'normalized', ...
    'Position', [LX 0.875 0.105 0.045], 'String', 'Select all', ...
    'FontName', FONT_NAME, 'FontSize', 10, 'Callback', @(~,~) setAll(hFig, true));
uicontrol(hFig, 'Style', 'pushbutton', 'Units', 'normalized', ...
    'Position', [LX+0.115 0.875 0.105 0.045], 'String', 'Clear all', ...
    'FontName', FONT_NAME, 'FontSize', 10, 'Callback', @(~,~) setAll(hFig, false));
uicontrol(hFig, 'Style', 'pushbutton', 'Units', 'normalized', ...
    'Position', [LX+0.23 0.875 0.105 0.045], 'String', 'Save PNG', ...
    'FontName', FONT_NAME, 'FontSize', 10, 'Callback', @(~,~) savePNG(hFig));

% ---- Checkbox grid (packed tight so all joints fit) ----
pnl = uipanel(hFig, 'Title', 'Joints', 'Units', 'normalized', ...
    'Position', [LX 0.04 LW 0.81], 'BackgroundColor', 'w', ...
    'FontName', FONT_NAME, 'FontSize', 11, 'FontWeight', 'bold');

nRows = ceil(nJoints / CB_COLUMNS);
cw = 1 / CB_COLUMNS;
ch = 1 / nRows;
cb = gobjects(nJoints, 1);
for i = 1:nJoints
    col = floor((i-1) / nRows);          % column-major fill
    row = mod((i-1), nRows);
    if CB_COLOR_BY_CURVE, txtColor = colors(i, :); else, txtColor = CB_TEXT_COLOR; end
    initOn = START_ALL_ON || any(strcmp(labels{i}, DEFAULT_ON_JOINTS));
    cb(i) = uicontrol(pnl, 'Style', 'checkbox', 'Units', 'normalized', ...
        'Position', [col*cw + 0.01, 1 - (row+1)*ch, cw - 0.015, ch*0.92], ...
        'String', labels{i}, 'Value', initOn, ...
        'BackgroundColor', 'w', 'ForegroundColor', txtColor, ...
        'FontName', FONT_NAME, 'FontSize', CB_FONT_SIZE, ...
        'Callback', @(~,~) updateVis(hFig));
end

% ---- Stash state for the callbacks, then draw ----
S = struct('ax', ax, 'cb', cb, 'hLine', hLine, 'hScat', hScat, ...
           'styleDD', styleDD, 'styleItems', {styleItems}, 'labels', {labels}, ...
           'n', nJoints, 'LEGEND_ON', LEGEND_ON, 'LEGEND_SIZE', LEGEND_SIZE, ...
           'FONT_NAME', FONT_NAME, 'subjectLabel', subjectLabel, ...
           'ikDir', ikDir, 'EXPORT_RESOLUTION', EXPORT_RESOLUTION);
guidata(hFig, S);
updateVis(hFig);

fprintf('Ready: %d joints loaded for %s.\n', nJoints, subjectLabel);

%% ========================================================================
%  LOCAL FUNCTIONS
%% ========================================================================
function updateVis(hFig)
% Apply the current style + checkbox states to every curve, rebuild legend.
    S = guidata(hFig);
    style   = S.styleItems{S.styleDD.Value};
    useLine = any(strcmp(style, {'Line', 'Both'}));
    useScat = any(strcmp(style, {'Scatter', 'Both'}));
    legH = []; legN = {};
    for i = 1:S.n
        on = (S.cb(i).Value == 1);
        set(S.hLine(i), 'Visible', tf2vis(on && useLine));
        set(S.hScat(i), 'Visible', tf2vis(on && useScat));
        if on
            if useLine, legH(end+1) = S.hLine(i); else, legH(end+1) = S.hScat(i); end %#ok<AGROW>
            legN{end+1} = S.labels{i};                                                %#ok<AGROW>
        end
    end
    if S.LEGEND_ON && ~isempty(legH)
        legend(S.ax, legH, legN, 'Location', 'eastoutside', ...
            'FontSize', S.LEGEND_SIZE, 'FontName', S.FONT_NAME, 'Interpreter', 'none');
    else
        legend(S.ax, 'off');
    end
end

function setAll(hFig, val)
% Tick (val=true) or untick (val=false) every joint checkbox.
    S = guidata(hFig);
    for i = 1:S.n, S.cb(i).Value = val; end
    updateVis(hFig);
end

function savePNG(hFig)
% Export the current figure to Results/Subject N/Figures.
    S = guidata(hFig);
    figDir = fullfile(fileparts(S.ikDir), 'Figures');
    if ~exist(figDir, 'dir'), mkdir(figDir); end
    pngFile = fullfile(figDir, ['JointAngles_' strrep(S.subjectLabel, ' ', '') '.png']);
    exportgraphics(hFig, pngFile, 'Resolution', S.EXPORT_RESOLUTION);
    fprintf('PNG saved: %s\n', pngFile);
end

function v = tf2vis(tf)
    if tf, v = 'on'; else, v = 'off'; end
end

function applyAxStyle(ax, fontName, tickSize, lineWidth, gridOn)
    ax.FontName   = fontName;
    ax.FontSize   = tickSize;
    ax.FontWeight = 'bold';
    ax.LineWidth  = lineWidth;
    ax.Box        = 'on';
    if gridOn, grid(ax, 'on'); end
end

%% ----- parse an OpenSim .mot/.sto file -----
function [t, data, labels] = readMot(file)
    fid = fopen(file, 'r');
    if fid < 0, error('Could not open %s', file); end
    line = fgetl(fid);
    while ischar(line) && ~strcmpi(strtrim(line), 'endheader')
        line = fgetl(fid);
    end
    labels = strsplit(strtrim(fgetl(fid)), sprintf('\t'));   % column names
    M = cell2mat(textscan(fid, repmat('%f', 1, numel(labels)), ...
                          'Delimiter', '\t', 'CollectOutput', true));
    fclose(fid);
    t      = M(:, 1);
    data   = M(:, 2:end);
    labels = labels(2:end);     % drop the 'time' label
end
