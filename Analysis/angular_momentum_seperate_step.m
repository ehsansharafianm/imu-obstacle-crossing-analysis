clc; clear; close all;
import org.opensim.modeling.*
addpath(fileparts(mfilename('fullpath')));
scriptTimer = tic;                         % measure total processing time

%% ========================================================================
%% STEP 6 - Angular momentum from the OpenSim IK motion
%% ========================================================================
% Whole-body AND segmental angular momentum about the body centre of mass (COM),
% in the model Ground frame. Purely KINEMATIC + INERTIAL - no ground-reaction or
% muscle forces needed (ideal for IMU-only data).
%
% Reads ONLY existing step-1 outputs; it does not modify steps 1-5.
%
% For each body:  H_i = R*I_i*R'*w_i  +  m_i (r_i - r_com) x (v_i - v_com)
%   (spin term = segment rotating about its own COM; orbital term = its mass
%    swinging around the whole-body COM). The whole-body WBAM is the sum over all
%   segments - cross-checked against Simbody's calcSystemCentralMomentum.
% Segments are also pooled into Arms / Legs / Trunk groups.

%% ===================== BODY FEATURES =====================
% Two ways to supply the subject anthropometrics:
%   ASK_BODY_FEATURES = false -> use the BODY.* defaults hard-coded below.
%   ASK_BODY_FEATURES = true  -> you are prompted for each at run time
%                                (press Enter at a prompt to keep the default).
% Body MASS only rescales the ABSOLUTE (kg*m^2/s) values; the dimensionless
% momentum is mass-scale invariant. Speed & leg length set the normalization.
ASK_BODY_FEATURES = false;
BODY.mass_kg   = 70;      % subject body mass (kg)   - absolute rescale only
BODY.height_m  = 1.75;    % subject height (m)       - used for leg length if blank
BODY.legLen_m  = [];      % leg length (m); [] -> estimated as 0.53*height
BODY.speed_mps = [];      % mean walking speed (m/s); [] -> derived from ZHC, else fallback
SPEED_FALLBACK = 1.2;     % walking speed used ONLY if not supplied and ZHC unavailable

%% ===================== PROCESSING SETTINGS =====================
LOWPASS_HZ = 6;           % zero-phase low-pass on coordinates before differentiation (Hz)
FILT_ORDER = 4;           % Butterworth order
% ===============================================================

tn = input('  Input Test Number: ');
if ASK_BODY_FEATURES, BODY = askBody(BODY); end

%% ---- resolve inputs (all produced by step 1) ----
root      = fileparts(fileparts(mfilename('fullpath')));
osimDir   = fullfile(root,'Results','OpenSim Outputs',   ['Test ' num2str(tn)]);
base      = fullfile(root,'Results','Parameters Output', ['Test ' num2str(tn)]);
modelFile = fullfile(osimDir,'Rajagopal_2015_calibrated.osim');
if ~isfile(modelFile), error('Calibrated model not found:\n  %s\n(Run step 1 for Test %d.)', modelFile, tn); end
mots = dir(fullfile(osimDir,'IKResults','ik_*.mot'));
if isempty(mots), error('No ik_*.mot in %s\n(Run step 1 for Test %d.)', fullfile(osimDir,'IKResults'), tn); end
[~,newest] = max([mots.datenum]);
motFile = fullfile(mots(newest).folder, mots(newest).name);
fprintf('Model : %s\nMotion: %s\n', modelFile, motFile);

%% ---- load model ----
model  = Model(modelFile);
state  = model.initSystem();
Mmodel = model.getTotalMass(state);
matter = model.getMatterSubsystem();
cs     = model.updCoordinateSet();
nCoord = cs.getSize();

%% ---- read IK motion (.mot) ----
[ikTime, Qraw, coordNames] = readMot(motFile);
nT = numel(ikTime);
dt = median(diff(ikTime));
fs = 1/dt;
fprintf('IK: %d frames @ %.1f Hz  (%.2f s)\n', nT, fs, ikTime(end)-ikTime(1));

% Map .mot columns to model coordinate handles; flag translational columns.
colHandle = cell(1,numel(coordNames));
isRot     = true(1,numel(coordNames));
for c = 1:numel(coordNames)
    for i = 0:nCoord-1
        if strcmp(char(cs.get(i).getName()), coordNames{c})
            colHandle{c} = cs.get(i); break;
        end
    end
    isRot(c) = ~(endsWith(coordNames{c},'_tx') || endsWith(coordNames{c},'_ty') || endsWith(coordNames{c},'_tz'));
end

% Units: rotational coords deg -> rad (translational stay metres).
Q = Qraw;
Q(:,isRot) = deg2rad(Qraw(:,isRot));

% Zero-phase low-pass, then central-difference for generalized speeds.
[b,a] = butter(FILT_ORDER, LOWPASS_HZ/(fs/2));
Qf = filtfilt(b,a,Q);
U  = zeros(size(Qf));
for c = 1:size(Qf,2), U(:,c) = gradient(Qf(:,c), dt); end

%% ---- per-body constants (mass, COM, inertia in body frame, group) ----
bodies = model.getBodySet();
nB     = bodies.getSize();
bName  = cell(1,nB);  bMass = zeros(1,nB);  bGroup = cell(1,nB);
bComB  = cell(1,nB);  bIb   = cell(1,nB);
for k = 0:nB-1
    bd = bodies.get(k);
    bName{k+1}  = char(bd.getName());
    bMass(k+1)  = bd.getMass();
    bComB{k+1}  = bd.getMassCenter();                 % Vec3 (body frame)
    bIb{k+1}    = inertia33(bd.get_inertia());        % about COM, body frame (3x3), from Vec6
    bGroup{k+1} = groupOf(bName{k+1});
end

%% ---- angular momentum per frame (whole-body via segment sum + Simbody) ----
% NOTE: the per-body API calls below (findStation*InGround, getVelocityInGround,
% getTransformInGround, getInertia) are standard OpenSim 4.x Frame/Body methods.
% If your binding names any of them differently, that is the only place to touch.
Hseg     = zeros(nT,3,nB);     % per-segment H about COM (kg*m^2/s), [X Y Z]
H        = zeros(nT,3);        % whole-body = sum of segments
Hsimbody = nan(nT,3);          % cross-check (Simbody), if available
useSimbody = true;
ex0 = Vec3(1,0,0);  ey0 = Vec3(0,1,0);  ez0 = Vec3(0,0,1);   % body-frame basis (reused)
fprintf('Computing angular momentum over %d frames x %d bodies ...\n', nT, nB);
for f = 1:nT
    for c = 1:numel(coordNames)
        if isempty(colHandle{c}), continue; end
        colHandle{c}.setValue(state, Qf(f,c), false);   % false: skip constraint projection
        colHandle{c}.setSpeedValue(state, U(f,c));
    end
    model.realizeVelocity(state);

    comPos = vec3(model.calcMassCenterPosition(state));
    comVel = vec3(model.calcMassCenterVelocity(state));
    for k = 0:nB-1
        bd = bodies.get(k);
        m  = bMass(k+1);
        ri = vec3(bd.findStationLocationInGround(state, bComB{k+1}));   % segment COM position
        vi = vec3(bd.findStationVelocityInGround(state, bComB{k+1}));   % segment COM velocity
        w  = vec3(bd.getVelocityInGround(state).get(0));                % segment angular velocity
        R  = [vec3(bd.expressVectorInGround(state, ex0)), ...          % body->ground rotation
              vec3(bd.expressVectorInGround(state, ey0)), ...          % (columns = body axes in ground)
              vec3(bd.expressVectorInGround(state, ez0))];
        Ig = R * bIb{k+1} * R.';                                        % inertia in ground
        Hi = Ig*w + m*cross(ri - comPos, vi - comVel);                 % spin + orbital
        Hseg(f,:,k+1) = Hi.';
    end
    H(f,:) = sum(Hseg(f,:,:), 3);

    if useSimbody
        try
            ang = matter.calcSystemCentralMomentum(state).get(0);
            Hsimbody(f,:) = [ang.get(0), ang.get(1), ang.get(2)];
        catch
            useSimbody = false;
            warning('calcSystemCentralMomentum unavailable - using the segment sum as whole-body WBAM.');
        end
    end
end

% Validation: segment sum should equal Simbody's whole-body momentum.
if useSimbody
    dmax = max(abs(H(:) - Hsimbody(:)));
    fprintf('Segment-sum vs Simbody WBAM: max abs diff = %.3g kg*m^2/s (should be ~0).\n', dmax);
end

%% ---- group into Arms / Legs / Trunk ----
groupLabels = {'Arms','Legs','Trunk'};
groupKeys   = {'Arm','Leg','Trunk'};
Hgrp = zeros(nT,3,numel(groupKeys));
for g = 1:numel(groupKeys)
    sel = strcmp(bGroup, groupKeys{g});
    if any(sel), Hgrp(:,:,g) = sum(Hseg(:,:,sel), 3); end
end

%% ---- normalization ----
if isempty(BODY.legLen_m), L = 0.53*BODY.height_m; else, L = BODY.legLen_m; end
V = BODY.speed_mps;
if isempty(V), V = deriveSpeed(base, tn, SPEED_FALLBACK); end
normFac = Mmodel * V * L;                 % dimensionless divisor (mass-scale invariant)
Hn      = H    ./ normFac;
Hseg_n  = Hseg ./ normFac;
Hgrp_n  = Hgrp ./ normFac;
Habs    = H    .* (BODY.mass_kg / Mmodel);
fprintf('Model mass=%.1f kg | subject mass=%.1f kg | V=%.2f m/s | L=%.3f m\n', Mmodel, BODY.mass_kg, V, L);
fprintf('Peak |WBAM| = %.3f kg*m^2/s ; peak normalized = %.4f\n', max(vecnorm(H,2,2)), max(vecnorm(Hn,2,2)));

%% ---- save (.mat + .xlsx) ----
AM = struct();
AM.test = tn;  AM.time = ikTime;  AM.fs = fs;
AM.axes = '[X Y Z] in the model Ground frame';   AM.units_H = 'kg*m^2/s';
AM.H_model = H;  AM.H_subject = Habs;  AM.H_norm = Hn;  AM.Hmag = vecnorm(H,2,2);
AM.seg.names = bName;  AM.seg.group = bGroup;  AM.seg.mass_kg = bMass;
AM.seg.H = Hseg;       AM.seg.H_norm = Hseg_n;     % nT x 3 x nBody
AM.group.labels = groupLabels;  AM.group.H = Hgrp;  AM.group.H_norm = Hgrp_n;   % nT x 3 x 3
AM.modelMass_kg = Mmodel;  AM.speed_mps = V;  AM.legLen_m = L;  AM.body = BODY;
if ~isfolder(base), mkdir(base); end
save(fullfile(base, sprintf('AngularMomentum_Test%d.mat', tn)), 'AM');

% Excel: whole-body + group components (per-segment stays in the .mat).
Tvars = {'time_s','WB_Hx','WB_Hy','WB_Hz'};
Tdata = [ikTime, H];
for g = 1:numel(groupLabels)
    Tvars = [Tvars, {sprintf('%s_Hx',groupLabels{g}), sprintf('%s_Hy',groupLabels{g}), sprintf('%s_Hz',groupLabels{g})}]; %#ok<AGROW>
    Tdata = [Tdata, Hgrp(:,:,g)]; %#ok<AGROW>
end
writetable(array2table(round(Tdata,6),'VariableNames',Tvars), ...
           fullfile(base, sprintf('AngularMomentum_Test%d.xlsx', tn)));

%% ---- interactive viewer (toggle segments / groups / whole-body) ----
% Build the entity list: whole body, the three groups, then every segment.
ent = struct('name',{},'raw',{},'norm',{});
ent(end+1) = struct('name','Whole body', 'raw',H, 'norm',Hn);
for g = 1:numel(groupLabels)
    ent(end+1) = struct('name',groupLabels{g}, 'raw',Hgrp(:,:,g), 'norm',Hgrp_n(:,:,g)); %#ok<SAGROW>
end
for k = 1:nB
    if bMass(k) <= 0, continue; end                       % skip massless frames
    ent(end+1) = struct('name',bName{k}, 'raw',Hseg(:,:,k), 'norm',Hseg_n(:,:,k)); %#ok<SAGROW>
end
defOn = [{'Whole body'}, groupLabels];                     % start with WB + groups
amViewer(sprintf('Angular momentum - segments & groups | Test %d', tn), ...
         ikTime, ent, defOn, base, tn);

fprintf('Saved AngularMomentum_Test%d.mat / .xlsx and viewer figure to:\n  %s\n', tn, base);
fprintf('Total processing time: %.1f s\n', toc(scriptTimer));

%% ========================================================================
%  LOCAL FUNCTIONS
%% ========================================================================
function v = vec3(V)          % SimTK Vec3 -> 3x1 double
    v = [V.get(0); V.get(1); V.get(2)];
end

function I = inertia33(v6)    % SimTK Vec6 [Ixx Iyy Izz Ixy Ixz Iyz] -> symmetric 3x3
    Ixx=v6.get(0); Iyy=v6.get(1); Izz=v6.get(2);
    Ixy=v6.get(3); Ixz=v6.get(4); Iyz=v6.get(5);
    I = [Ixx Ixy Ixz;  Ixy Iyy Iyz;  Ixz Iyz Izz];
end

function g = groupOf(name)    % body name -> Arm / Leg / Trunk / Other
    n = lower(name);
    if     contains(n,'humerus')||contains(n,'ulna')||contains(n,'radius')||contains(n,'hand')
        g = 'Arm';
    elseif contains(n,'femur')||contains(n,'tibia')||contains(n,'talus')||contains(n,'calcn')||contains(n,'toes')||contains(n,'patella')
        g = 'Leg';
    elseif contains(n,'pelvis')||contains(n,'torso')||contains(n,'lumbar')||contains(n,'head')||contains(n,'thorax')||contains(n,'abdomen')
        g = 'Trunk';
    else
        g = 'Other';
    end
end

function BODY = askBody(BODY)
    BODY.mass_kg  = promptNum('Subject mass (kg)',                        BODY.mass_kg);
    BODY.height_m = promptNum('Subject height (m)',                       BODY.height_m);
    BODY.legLen_m = promptNum('Leg length (m)  [blank = 0.53*height]',    BODY.legLen_m);
    BODY.speed_mps= promptNum('Walking speed (m/s)  [blank = derive/ZHC]',BODY.speed_mps);
end

function v = promptNum(label, def)
    if isempty(def), ds = 'blank'; else, ds = num2str(def); end
    s = input(sprintf('  %s [%s]: ', label, ds), 's');
    if isempty(strtrim(s)), v = def; else, v = str2double(s); end
end

function V = deriveSpeed(base, tn, fallback)
% Mean forward walking speed from the step-5 ZHC continuous foot path.
    V = fallback;
    f = fullfile(base, sprintf('SegTrajectories_SideBased_Test%d.mat', tn));
    if ~isfile(f), return; end
    try
        S = load(f,'S5').S5;
        if isfield(S,'zhc') && isfield(S.zhc,'L') && isfield(S.zhc.L,'pCont') && ~isempty(S.zhc.L.pCont)
            p = S.zhc.L.pCont;  t = S.zhc.L.tCont;
            d = sum(sqrt(sum(diff(p(:,1:2)).^2,2)), 'omitnan');
            T = t(end) - t(1);
            if T > 0 && d > 0, V = d / T; end
        end
    catch
    end
end

function [t, data, labels] = readMot(file)
    fid = fopen(file,'r'); if fid < 0, error('Cannot open %s', file); end
    line = fgetl(fid);
    while ischar(line) && ~strcmpi(strtrim(line),'endheader'), line = fgetl(fid); end
    labels = strsplit(strtrim(fgetl(fid)), sprintf('\t'));
    C = cell2mat(textscan(fid, repmat('%f',1,numel(labels)), 'Delimiter','\t','CollectOutput',true));
    fclose(fid);
    t = C(:,1); data = C(:,2:end); labels = labels(2:end);
end

%% ----- interactive viewer -----
function amViewer(titleStr, time, ent, defOn, figDir, tn)
% Toggle which entities (whole body / Arms-Legs-Trunk / individual segments) and
% which axes (X, Y, Z, |H|) to display; switch raw <-> normalized units.
    nE = numel(ent);
    if exist('turbo','file'), colors = turbo(nE); else, colors = hsv(nE); end
    axNames = {'X','Y','Z','|H|'};  axMarkers = {'o','s','^','d'};

    hF = figure('Color','w','Name',titleStr,'Position',[80 80 1360 800]);
    ax = axes(hF,'Position',[0.40 0.11 0.57 0.80]); hold(ax,'on');
    LX = 0.02;  LW = 0.34;

    % axis (component) checkboxes
    uicontrol(hF,'Style','text','Units','normalized','Position',[LX 0.955 0.09 0.03], ...
        'String','Axes:','BackgroundColor','w','FontWeight','bold','HorizontalAlignment','left');
    axCb = gobjects(4,1);
    for a = 1:4
        axCb(a) = uicontrol(hF,'Style','checkbox','Units','normalized', ...
            'Position',[LX+0.08+(a-1)*0.065, 0.955, 0.062, 0.03], 'String',axNames{a}, ...
            'Value', a==1, 'BackgroundColor','w','FontWeight','bold', ...
            'Callback',@(~,~) redraw());
    end

    % units popup
    uicontrol(hF,'Style','text','Units','normalized','Position',[LX 0.915 0.09 0.03], ...
        'String','Units:','BackgroundColor','w','FontWeight','bold','HorizontalAlignment','left');
    unitDD = uicontrol(hF,'Style','popupmenu','Units','normalized','Position',[LX+0.08 0.917 0.25 0.03], ...
        'String',{'Raw (kg*m^2/s)','Normalized (/ m V L)'},'Value',1,'Callback',@(~,~) redraw());

    % select-all / clear-all / save
    uicontrol(hF,'Style','pushbutton','Units','normalized','Position',[LX 0.87 0.105 0.038], ...
        'String','Select all','Callback',@(~,~) setAll(true));
    uicontrol(hF,'Style','pushbutton','Units','normalized','Position',[LX+0.115 0.87 0.105 0.038], ...
        'String','Clear all','Callback',@(~,~) setAll(false));
    uicontrol(hF,'Style','pushbutton','Units','normalized','Position',[LX+0.23 0.87 0.105 0.038], ...
        'String','Save PNG','Callback',@(~,~) savePNG());

    % entity checkbox panel (whole body / groups / segments)
    pnl = uipanel(hF,'Title','Entities','Units','normalized','Position',[LX 0.04 LW 0.81], ...
        'BackgroundColor','w','FontWeight','bold');
    nCol = 2;  nRow = ceil(nE/nCol);  cw = 1/nCol;  ch = 1/nRow;
    entCb = gobjects(nE,1);
    for i = 1:nE
        col = floor((i-1)/nRow);  row = mod(i-1,nRow);
        entCb(i) = uicontrol(pnl,'Style','checkbox','Units','normalized', ...
            'Position',[col*cw+0.01, 1-(row+1)*ch, cw-0.015, ch*0.92], ...
            'String',ent(i).name,'Value',any(strcmp(ent(i).name,defOn)), ...
            'ForegroundColor',[0 0 0],'BackgroundColor','w', ...
            'Callback',@(~,~) redraw());
    end

    redraw();

    function redraw()
        cla(ax); hold(ax,'on');
        selAx = find(arrayfun(@(h) h.Value==1, axCb));
        raw   = unitDD.Value == 1;
        multiA = numel(selAx) > 1;
        legH = []; legN = {};
        for i = 1:nE
            if entCb(i).Value ~= 1, continue; end
            if raw, D = ent(i).raw; else, D = ent(i).norm; end
            for a = selAx(:)'
                if a <= 3, y = D(:,a); else, y = vecnorm(D,2,2); end
                mk = 'none'; if multiA, mk = axMarkers{a}; end
                if strcmp(mk,'none')
                    h = plot(ax, time, y, '-', 'Color', colors(i,:), 'LineWidth', 1.6);
                else
                    step = max(1, round(numel(time)/25));
                    h = plot(ax, time, y, '-', 'Color', colors(i,:), 'LineWidth', 1.6, ...
                             'Marker', mk, 'MarkerIndices', 1:step:numel(time), 'MarkerSize', 5);
                end
                legH(end+1) = h; %#ok<AGROW>
                if multiA, legN{end+1} = [ent(i).name ' - ' axNames{a}]; else, legN{end+1} = ent(i).name; end %#ok<AGROW>
            end
        end
        grid(ax,'on'); box(ax,'on'); ax.FontWeight='bold';
        xlabel(ax,'Time (s)','FontWeight','bold','FontSize',13);
        if raw, yl = 'Angular momentum  (kg\cdotm^2/s)'; else, yl = 'Normalized angular momentum'; end
        ylabel(ax,yl,'FontWeight','bold','FontSize',13);
        title(ax,titleStr,'FontWeight','bold','FontSize',15,'Interpreter','none');
        if ~isempty(legH)
            legend(ax, legH, legN, 'Location','eastoutside','Interpreter','none','FontSize',9);
        else
            legend(ax,'off');
        end
    end

    function setAll(val)
        for i = 1:nE, entCb(i).Value = val; end
        redraw();
    end

    function savePNG()
        if ~exist(figDir,'dir'), mkdir(figDir); end
        pngFile = fullfile(figDir, sprintf('AngularMomentum_Segments_Test%d.png', tn));
        exportgraphics(hF, pngFile, 'Resolution', 300);
        fprintf('PNG saved: %s\n', pngFile);
    end
end
