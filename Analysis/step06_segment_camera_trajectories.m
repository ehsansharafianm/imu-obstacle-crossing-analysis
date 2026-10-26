clc
close all
addpath(fileparts(mfilename('fullpath')));

%% ========================================================================
%% STEP 6 - Segment the camera marker trajectories into strides
%% ========================================================================
% Same stride segmentation as step 4, applied to the camera-reconstructed foot
% markers (from step 5) instead of the IMU/joint signals. Uses the SAME ZVP
% (zero-velocity) stride boundaries step 4 detected and saved, so camera strides
% line up with the IMU/joint strides. Only the four foot markers are segmented
% (L/R toe & heel); obstacle markers are not.
%   LEFT markers  (L_toe, L_heel)  -> Left Foot (Dot) ZVPs   (Seg.zvpL)
%   RIGHT markers (R_toe, R_heel)  -> Right Foot (Dot) ZVPs  (Seg.zvpR)
% Each marker's X/Y/Z is cut at its side's ZVPs and (a) time-normalized to
% Seg.nseg points (0-100% gait cycle) and (b) kept raw in the time domain.
%
% Inputs (run first):
%   CameraSynced_TestN.mat   (Cam)  - step 5   [camera markers on the 60 Hz grid]
%   SegmentedParams_TestN.mat (Seg) - step 4   [Seg.zvpL/zvpR, nseg, pct, timeAxis]
% Output:
%   CameraSegmented_TestN.mat (CamSeg) + optional PNGs (Save PNG buttons).

%% ===================== SETTINGS =====================
MARKERS   = {'L_toe','L_heel','R_toe','R_heel'};
SIDE      = {'L','L','R','R'};
INTERP    = 'linear';        % normalized-grid interpolation (camera is gappy)
DEFAULT_MK   = {'L_toe','L_heel','ZHC L foot'};
FONT_NAME = 'Arial';
MK_COLOR = struct('L_toe',[0.45 0.20 0.70], 'L_heel',[0.15 0.55 0.20], ...
                  'R_toe',[0.80 0.15 0.15], 'R_heel',[0.90 0.55 0.10]);

%% ===================== INPUT + LOAD =====================
% Set TN before running (e.g. `TN = 22;`) to skip the prompt for batch runs.
if exist('TN','var') && ~isempty(TN), tn = TN; else, tn = input('  Input Test Number: '); end
root = fileparts(fileparts(mfilename('fullpath')));
base = fullfile(root, 'Results','Parameters Output', ['Test ' num2str(tn)]);
if ~isfolder(base)
    base2 = fullfile('..','Results','Parameters Output', ['Test ' num2str(tn)]);
    if isfolder(base2), base = base2; end
end
camFile = fullfile(base, sprintf('CameraSynced_Test%d.mat', tn));
segFile = fullfile(base, sprintf('SegmentedParams_Test%d.mat', tn));
if ~isfile(camFile), error('Not found: %s  (run step 5 for Test %d first).', camFile, tn); end
if ~isfile(segFile), error('Not found: %s  (run step 4 for Test %d first).', segFile, tn); end
load(camFile, 'Cam');
load(segFile, 'Seg');
tCam  = Cam.time(:);
NSEG  = Seg.nseg;  pct = Seg.pct(:);  tvec = Seg.timeAxis(:);  maxLen = numel(tvec);
zvp = struct('L', Seg.zvpL(:), 'R', Seg.zvpR(:));   % one assignment (avoids clashing
                                                    % with a leftover numeric 'zvp' from step 4)
fprintf('Segmenting camera markers for Test %d:  Left ZVP=%d, Right ZVP=%d, NSEG=%d\n', ...
        tn, numel(zvp.L), numel(zvp.R), NSEG);

%% ===================== SEGMENT EACH MARKER (X/Y/Z) =====================
% M(k): name, side, color, norm{a} (NSEG x nStr), time{a} (maxLen x nStr) for a=1:3
M = struct('name',{},'side',{},'color',{},'norm',{},'time',{}, ...
           'meanN',{},'sdN',{},'meanT',{},'sdT',{},'nStr',{});
for k = 1:numel(MARKERS)
    m = MARKERS{k}; sd = SIDE{k}; G = Cam.markers.(m); z = zvp.(sd);
    nrm = cell(1,3); tim = cell(1,3);
    mN = nan(NSEG,3); sN = nan(NSEG,3); mT = nan(maxLen,3); sT = nan(maxLen,3); nStr = zeros(1,3);
    for a = 1:3
        nrm{a} = segmentAll(tCam, G(:,a), z, NSEG, INTERP);
        tim{a} = segmentAllTime(G(:,a), z, maxLen);
        mN(:,a) = mean(nrm{a},2,'omitnan');  sN(:,a) = std(nrm{a},0,2,'omitnan');
        mT(:,a) = mean(tim{a},2,'omitnan');  sT(:,a) = std(tim{a},0,2,'omitnan');
        nStr(a) = size(nrm{a},2);
    end
    M(k) = struct('name',m,'side',sd,'color',MK_COLOR.(m),'norm',{nrm},'time',{tim}, ...
                  'meanN',mN,'sdN',sN,'meanT',mT,'sdT',sT,'nStr',nStr);
    fprintf('  %-10s (%s): %d strides (Z)\n', m, sd, nStr(3));
end

%% ===================== ADD ZHC (IMU-integrated foot, from step 4) =====================
% Already segmented per stride in step 4: Seg.zhc.<side>.posGait (NSEG x 3 x nWin)
% and .posTime (maxLen x 3 x nWin), in metres -> mm. Same windows as the camera.
if isfield(Seg,'zhc')
    zColor = struct('L',[0 0 0], 'R',[0.85 0.10 0.60]);
    for side = {'L','R'}
        sd = side{1};
        if ~isfield(Seg.zhc, sd), continue; end
        Z = Seg.zhc.(sd);
        pg = Z.posGait*1000;  ptm = Z.posTime*1000;   % m -> mm
        nrm = cell(1,3); tim = cell(1,3);
        mN = nan(NSEG,3); sN = nan(NSEG,3); mT = nan(maxLen,3); sT = nan(maxLen,3); nStr = zeros(1,3);
        for a = 1:3
            nrm{a} = reshape(pg(:,a,:),  size(pg,1),  []);
            tim{a} = reshape(ptm(:,a,:), size(ptm,1), []);
            mN(:,a) = mean(nrm{a},2,'omitnan');  sN(:,a) = std(nrm{a},0,2,'omitnan');
            mT(:,a) = mean(tim{a},2,'omitnan');  sT(:,a) = std(tim{a},0,2,'omitnan');
            nStr(a) = size(nrm{a},2);
        end
        nm = sprintf('ZHC %s foot', sd);
        M(end+1) = struct('name',nm,'side',sd,'color',zColor.(sd),'norm',{nrm},'time',{tim}, ...
                          'meanN',mN,'sdN',sN,'meanT',mT,'sdT',sT,'nStr',nStr); %#ok<SAGROW>
        fprintf('  %-10s (%s): %d windows (Z)\n', nm, sd, nStr(3));
    end
end

%% ===================== SAVE =====================
CamSeg = struct('test',tn,'fs',Cam.fs,'nseg',NSEG,'pct',pct,'timeAxis',tvec, ...
                'markers',{{M.name}},'side',{{M.side}},'seg',M);
outMat = fullfile(base, sprintf('CameraSegmented_Test%d.mat', tn));
save(outMat, 'CamSeg');
fprintf('Saved %s\n', outMat);

%% ===================== VIEWERS =====================
buildSegViewer(sprintf('Camera strides - normalized (0-100%%)  |  Test %d', tn), ...
    M, pct, 'norm', DEFAULT_MK, FONT_NAME, base, tn, 'Gait cycle (%)', 100, 'CameraStrideNormalized');
buildSegViewer(sprintf('Camera strides - time domain (s)  |  Test %d', tn), ...
    M, tvec, 'time', DEFAULT_MK, FONT_NAME, base, tn, 'Time (s)', tvec(end), 'CameraStrideTime');
fprintf('Ready: normalized (0-100%%) and time-domain camera stride viewers.\n');

%% ========================================================================
%  LOCAL FUNCTIONS
%% ========================================================================
function A = segmentAll(t, y, zvp, Nseg, method)
% Strides between consecutive ZVPs, normalized to Nseg points. NaN-safe.
    nStr = numel(zvp) - 1;
    if nStr < 1, A = nan(Nseg,1); return; end
    A = nan(Nseg, nStr);
    for s = 1:nStr
        a = zvp(s); b = zvp(s+1);
        if b <= a+1, continue; end
        tt = t(a:b); seg = y(a:b);
        ok = ~isnan(seg);
        if nnz(ok) < 2, continue; end
        tq = linspace(tt(1), tt(end), Nseg);
        A(:,s) = interp1(tt(ok), seg(ok), tq, method);   % outside finite range -> NaN
    end
    A(:, all(isnan(A),1)) = [];
    if isempty(A), A = nan(Nseg,1); end
end

function A = segmentAllTime(y, zvp, maxLen)
% Raw strides between consecutive ZVPs, NaN-padded to maxLen rows.
    nStr = numel(zvp) - 1;
    if nStr < 1, A = nan(maxLen,1); return; end
    A = nan(maxLen, nStr);
    for s = 1:nStr
        a = zvp(s); b = zvp(s+1);
        if b <= a+1, continue; end
        seg = y(a:b);  nkeep = min(numel(seg), maxLen);
        A(1:nkeep, s) = seg(1:nkeep);
    end
    A(:, all(isnan(A),1)) = [];
    if isempty(A), A = nan(maxLen,1); end
end

%% ----- segmentation viewer (markers x axis, All strides / Mean +/- SD) -----
function buildSegViewer(titleStr, M, xvec, domain, defMk, fontName, figDir, tn, xlab, xmax, pngTag)
    nM = numel(M);
    hF = figure('Color','w','Name',titleStr,'Position',[80 80 1400 800]);
    ax = axes(hF,'Position',[0.255 0.10 0.70 0.82]);
    LX = 0.012; PW = 0.205; axNames = {'X','Y','Z'};
    % axis selector (default Z = height)
    uicontrol(hF,'Style','text','Units','normalized','Position',[LX 0.955 0.05 0.03], ...
        'String','Axis:','BackgroundColor','w','FontName',fontName,'FontWeight','bold','HorizontalAlignment','left');
    axCb = gobjects(3,1);
    for a = 1:3
        axCb(a) = uicontrol(hF,'Style','checkbox','Units','normalized', ...
            'Position',[LX+0.045+(a-1)*0.045, 0.955, 0.045, 0.03],'String',axNames{a}, ...
            'Value',double(a==3),'BackgroundColor','w','FontName',fontName,'FontWeight','bold','Callback',@(~,~) updSeg(hF));
    end
    % display mode
    dispItems = {'All strides','Mean +/- SD'};
    dispDD = uicontrol(hF,'Style','popupmenu','Units','normalized','Position',[LX 0.912 0.19 0.03], ...
        'String',dispItems,'Value',1,'FontName',fontName,'Callback',@(~,~) updSeg(hF));
    % buttons
    uicontrol(hF,'Style','pushbutton','Units','normalized','Position',[LX 0.872 0.06 0.03], ...
        'String','All','FontName',fontName,'Callback',@(~,~) setAllSV(hF,true));
    uicontrol(hF,'Style','pushbutton','Units','normalized','Position',[LX+0.065 0.872 0.06 0.03], ...
        'String','None','FontName',fontName,'Callback',@(~,~) setAllSV(hF,false));
    uicontrol(hF,'Style','pushbutton','Units','normalized','Position',[LX+0.13 0.872 0.075 0.03], ...
        'String','Save PNG','FontName',fontName,'Callback',@(~,~) savePNGsv(hF));
    % marker checklist (coloured labels)
    pnl = uipanel(hF,'Title','Markers','Units','normalized','Position',[LX 0.03 PW 0.83], ...
        'BackgroundColor','w','FontName',fontName,'FontSize',11,'FontWeight','bold');
    rh = 1/max(nM,1); cb = gobjects(nM,1);
    for k = 1:nM
        cb(k) = uicontrol(pnl,'Style','checkbox','Units','normalized','Position',[0.06 1-k*rh 0.9 rh*0.9], ...
            'String',M(k).name,'Value',double(any(strcmp(M(k).name,defMk))), ...
            'ForegroundColor',M(k).color,'BackgroundColor','w','FontName',fontName,'FontSize',11, ...
            'FontWeight','bold','Callback',@(~,~) updSeg(hF));
    end
    S = struct('ax',ax,'cb',cb,'axCb',axCb,'dispDD',dispDD,'dispItems',{dispItems}, ...
               'M',M,'nM',nM,'xvec',xvec,'domain',domain,'axNames',{axNames}, ...
               'titleStr',titleStr,'fontName',fontName,'figDir',figDir,'tn',tn, ...
               'xlab',xlab,'xmax',xmax,'pngTag',pngTag);
    guidata(hF, S); updSeg(hF);
end

function updSeg(hF)
    S = guidata(hF); ax = S.ax;
    meanMode = strcmp(S.dispItems{S.dispDD.Value}, 'Mean +/- SD');
    selA = find(arrayfun(@(h) h.Value==1, S.axCb));  multiA = numel(selA) > 1;
    lineSty = {'-','--',':'};
    x = S.xvec(:);
    cla(ax); hold(ax,'on'); legH = []; legN = {};
    for k = 1:S.nM
        if S.cb(k).Value ~= 1, continue; end
        c = S.M(k).color;
        for a = selA(:)'
            if strcmp(S.domain,'norm'), Y = S.M(k).norm{a}; else, Y = S.M(k).time{a}; end
            ls = '-'; if multiA, ls = lineSty{a}; end
            if meanMode
                m = mean(Y,2,'omitnan'); sdv = std(Y,0,2,'omitnan');
                good = ~isnan(m) & ~isnan(sdv);
                if any(good)
                    xf = [x(good); flipud(x(good))]; yf = [m(good)+sdv(good); flipud(m(good)-sdv(good))];
                    fill(ax, xf, yf, c, 'FaceAlpha',0.15, 'EdgeColor','none');
                end
                h = plot(ax, x, m, ls, 'Color', c, 'LineWidth', 2.4);
            else
                hh = plot(ax, x, Y, ls, 'Color', c, 'LineWidth', 1.0);
                if isempty(hh), continue; end
                h = hh(1);
            end
            legH(end+1) = h; %#ok<AGROW>
            if multiA, legN{end+1} = sprintf('%s %s', S.M(k).name, S.axNames{a}); else, legN{end+1} = S.M(k).name; end %#ok<AGROW>
        end
    end
    hold(ax,'off'); grid(ax,'on'); box(ax,'on'); ax.FontName = S.fontName; ax.FontSize = 12; ax.FontWeight = 'bold';
    xlabel(ax,S.xlab,'FontSize',15,'FontWeight','bold','FontName',S.fontName);
    ylabel(ax, segYLabel(selA, S.axNames), 'FontSize',15,'FontWeight','bold','FontName',S.fontName);
    title(ax,S.titleStr,'FontSize',16,'FontWeight','bold','FontName',S.fontName,'Interpreter','none');
    xlim(ax,[0 S.xmax]);
    if ~isempty(legH), legend(ax, legH, legN, 'Location','eastoutside','Interpreter','none','FontSize',10); else, legend(ax,'off'); end
end

function s = segYLabel(selA, axNames)
    desc = {'Lateral X (mm)','Walking Y (mm)','Height Z (mm)'};
    if numel(selA)==1, s = desc{selA}; else, s = 'Position (mm)'; end
    if isempty(selA), s = 'Position (mm)'; end
end

function setAllSV(hF, val), S = guidata(hF); for k=1:S.nM, S.cb(k).Value = val; end, updSeg(hF); end

function savePNGsv(hF)
    S = guidata(hF);
    if ~exist(S.figDir,'dir'), mkdir(S.figDir); end
    pngFile = fullfile(S.figDir, sprintf('%s_Test%d.png', S.pngTag, S.tn));
    exportgraphics(hF, pngFile, 'Resolution', 300);
    fprintf('PNG saved: %s\n', pngFile);
end
