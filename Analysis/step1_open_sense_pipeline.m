%% OpenSense_Pipeline.m
% Full OpenSense IMU pipeline for the Xsens Awinda system, in one script:
%   Step 1 - Convert raw Xsens .txt files to OpenSim .sto tables
%   Step 2 - Calibrate the model (place IMUs) from a static pose
%   Step 3 - Run inverse kinematics (orientation tracking)
%
% Run this script from the Analysis/ folder. Folder layout used:
%   ../Data/Subject <N>/      raw Xsens .txt (+ .mtb)              [input]
%   ../Results/Subject <N>/
%       STOFiles/             converted .sto signal files          [step 1]
%       Rajagopal_2015_calibrated.osim                             [step 2]
%       IKResults/            ik_*.mot + *_orientationErrors.sto    [step 3]
%   Setup/myIMUMappings.xml   sensor -> model body mapping
%   Model/Rajagopal_2015.osim generic model (+ Geometry/)
%
% Based on OpenSense example code by James Dunne (Stanford), Apache 2.0.
% ----------------------------------------------------------------------- %

%% Clear the workspace and import OpenSim
clear all; close all; clc;
import org.opensim.modeling.*
cd(fileparts(mfilename('fullpath')));   % always run from the Analysis folder

%% Close any leftover visualizer windows from previous runs.
% 'close all' only closes MATLAB figures; the OpenSim/Simbody 3D viewer is a
% separate OS process (simbody-visualizer.exe), so close it explicitly here.
if ispc
    [~, ~] = system('taskkill /F /IM simbody-visualizer.exe 2>NUL');
end

%% ===================== USER SETTINGS =====================
subjectNum           = input('Enter test number: ');
visChoice            = input('Show the 3D tracking visualization in Step 3? (y/n): ', 's');
visualizeTracking    = any(strcmpi(strtrim(visChoice), {'y', 'yes'}));  % default: no visualization
dedriftChoice        = input('Apply heading de-drift + re-run IK (for heading/turn-drift trials)? (y/n): ', 's');
applyDedrift         = any(strcmpi(strtrim(dedriftChoice), {'y', 'yes'}));  % writes IKResults_dedrift
sensorToOpenSim      = Vec3(-pi/2, 0, 0);  % rotation from IMU space to OpenSim world frame
baseIMUName          = 'pelvis_imu';       % base IMU that sets the heading (forward) direction
baseIMUHeading       = '-z';               % axis of the base IMU pointing forward
startTime            = [];                 % IK start time (s); [] = start of the recording
endTime              = [];                 % IK end time (s);   [] = end of the recording (full trial)
visualizeCalibration = false;              % calibration runs automatically (no viewer / no keypress)
freeCoords           = true;               % remove IK angle caps on the lower-limb coordinates
freeRangeDeg         = 180;                % widen freed coordinate range to +/- this (deg)
% --- Automatic .mtb -> .txt conversion (no manual MT Manager export needed) ---
convertMtb           = true;               % if an .mtb is in the test folder, convert it to per-IMU .txt first
pythonExe            = 'py -3.8';          % Python that has the Xsens 'xsensdeviceapi' wheel installed
converterScript      = fullfile(fileparts(mfilename('fullpath')), 'xsens_awinda_converter.py');
forceConvert         = false;              % re-convert even if the .txt are already newer than the .mtb
% =========================================================

%% Resolve folders for this subject
% Build ABSOLUTE paths from this script's own location (parent of Analysis is the
% project root). Do NOT use relative paths here: convertMtbToTxt passes the folder
% to abspath()/Java, whose working directory is fixed at MATLAB launch and does
% NOT follow cd - a relative '..\Data' would resolve against MATLAB's start folder
% (e.g. Documents\MATLAB), not the project.
subjectName = ['Test ' num2str(subjectNum)];
projRoot    = fileparts(fileparts(mfilename('fullpath')));                  % project root (parent of Analysis)
dataDir     = fullfile(projRoot, 'Data', 'Awinda IMUs', subjectName);      % raw input (absolute)
resultsRoot = fullfile(projRoot, 'Results', 'OpenSim Outputs', subjectName);% FINAL outputs (absolute)
if ~isfolder(dataDir)
    error('Raw data folder not found: %s', dataDir);
end
if ~isfolder(resultsRoot), mkdir(resultsRoot); end

% Convert any Xsens .mtb in the test folder to per-IMU .txt (MT Manager layout)
% with the Python xsensdeviceapi tool, so the rest of step 1 reads the .txt as
% before. No .mtb -> uses whatever .txt are already there (manual export).
if convertMtb
    convertMtbToTxt(dataDir, pythonExe, converterScript, forceConvert);
end

% OpenSim's native file I/O fails on very long paths (Windows 260-char limit),
% which the deep Google Drive folders exceed. So run all OpenSim steps in a
% SHORT local working folder, then copy the outputs back to resultsRoot.
workRoot = fullfile(tempdir, 'OpenSense', subjectName);
stoWork  = fullfile(workRoot, 'STOFiles');
ikWork   = fullfile(workRoot, 'IKResults');
geomWork = fullfile(workRoot, 'Geometry');
Logger.removeFileSink();                       % release any log held from a previous run
if isfolder(workRoot)
    [~, ~] = rmdir(workRoot, 's');             % best-effort clean (non-fatal if locked)
end
if ~isfolder(stoWork),  mkdir(stoWork);  end
if ~isfolder(ikWork),   mkdir(ikWork);   end
if ~isfolder(geomWork), mkdir(geomWork); end
copyfile(fullfile('Model','Rajagopal_2015.osim'), fullfile(workRoot,'Rajagopal_2015.osim'));
if isempty(dir(fullfile(geomWork,'*.vtp')))    % copy meshes once
    copyfile(fullfile('Model','Geometry'), geomWork);
end
ModelVisualizer.addDirToGeometrySearchPaths(geomWork);

% OpenSim diagnostic log -> local work folder (copied to Results at the end).
Logger.addFileSink(fullfile(workRoot, 'opensim.log'));

%% ===================== STEP 1: CONVERT XSENS DATA =====================
fprintf('\n=== Step 1: Converting Xsens data (%s) ===\n', subjectName);
% Custom reader: parse the Quat_q0..q3 columns straight from each sensor's
% .txt and write the orientations .sto ourselves. This bypasses OpenSim's
% XsensDataReader, which is picky about the exact MT Manager column layout.
DATA_RATE = 40;   % Awinda sample rate (Hz)

% Sensor -> model-body mapping, read straight from the OpenSense mappings XML.
sensorMap = readIMUMappings(fullfile('Setup', 'myIMUMappings.xml'));

% Auto-detect the trial prefix from the .txt files. The date/time in the
% filename (e.g. 2026-06-12_11h16) changes every session, so never hardcode it.
files = dir(fullfile(dataDir, 'MT_*.txt'));
if isempty(files)
    error('No MT_*.txt files found in %s', dataDir);
end
tok = regexp(files(1).name, '^(.*)_[0-9A-Fa-f]{8}\.txt$', 'tokens', 'once');
if isempty(tok)
    error('Could not parse trial prefix from file: %s', files(1).name);
end
trial = tok{1};
fprintf('Detected trial prefix: %s\n', trial);

% Read each sensor's quaternion columns.
nS        = numel(sensorMap);
bodyNames = cell(1, nS);
quatCells = cell(1, nS);          % each entry: N x 4  [q0 q1 q2 q3]
nF        = inf;
for s = 1:nS
    fp = findSensorFile(dataDir, trial, sensorMap(s).id);
    if isempty(fp)
        error('No file for sensor %s (body %s) in %s', ...
              sensorMap(s).id, sensorMap(s).body, dataDir);
    end
    q = readSensorQuat(fp);
    bodyNames{s} = sensorMap(s).body;
    quatCells{s} = q;
    nF = min(nF, size(q, 1));
    fprintf('  %-12s <- %s  (%d frames)\n', sensorMap(s).body, sensorMap(s).id, size(q, 1));
end

% Trim all sensors to the common frame count and build the time vector.
for s = 1:nS, quatCells{s} = quatCells{s}(1:nF, :); end
time = (0:nF-1)' / DATA_RATE;

% Write the OpenSim quaternion .sto.
orientationsFile = fullfile(stoWork, [trial '_orientations.sto']);
writeQuaternionSto(orientationsFile, time, bodyNames, quatCells, DATA_RATE);
fprintf('Wrote orientations to: %s\n', orientationsFile);
orientationsFile = abspath(orientationsFile);   % OpenSim needs an absolute path

% Trial extent for the IK time range (built from our own time vector).
nFrames   = nF;
dataStart = time(1);
dataEnd   = time(end);
fprintf('Trial duration: %.2f s  (%.3f to %.3f s, %d frames)\n', ...
        dataEnd - dataStart, dataStart, dataEnd, nFrames);

%% ===================== STEP 2: CALIBRATE MODEL =====================
fprintf('\n=== Step 2: Calibrating model ===\n');
origDir = pwd;  cd(workRoot);   % short C: cwd so Simbody can spawn the visualizer
modelFileName = abspath(fullfile(workRoot, 'Rajagopal_2015.osim'));   % local copy of the model

imuPlacer = IMUPlacer();
imuPlacer.set_model_file(modelFileName);
imuPlacer.set_orientation_file_for_calibration(orientationsFile);
imuPlacer.set_sensor_to_opensim_rotations(sensorToOpenSim);
imuPlacer.set_base_imu_label(baseIMUName);
imuPlacer.set_base_heading_axis(baseIMUHeading);
try
    imuPlacer.run(visualizeCalibration);
catch ME
    if visualizeCalibration
        warning('OpenSim visualizer could not start; calibrating without it.\n  (%s)', ME.message);
        imuPlacer.run(false);
    else
        rethrow(ME);
    end
end

% Save the calibrated model into the subject's Results folder.
[~, mName] = fileparts(modelFileName);
calibratedModelFile = abspath(fullfile(workRoot, [mName '_calibrated.osim']));
model = imuPlacer.getCalibratedModel();
if freeCoords
    % Unclamp the lower-limb coordinates so IK is not capped at the model's
    % joint range (OpenSim only enforces the range as an IK bound when the
    % coordinate is clamped). Widening the range is extra insurance.
    cs  = model.updCoordinateSet();
    lim = deg2rad(freeRangeDeg);
    nFreed = 0;
    for i = 0:cs.getSize()-1
        c = cs.get(i);
        if isLowerLimb(char(c.getName()))
            c.set_clamped(false);                 % property setter (no State needed)
            c.set_range(0, -lim);  c.set_range(1, lim);
            nFreed = nFreed + 1;
        end
    end
    fprintf('Freed %d lower-limb coordinate(s): unclamped, range +/- %g deg.\n', nFreed, freeRangeDeg);
end
model.print(calibratedModelFile);
fprintf('Wrote calibrated model to: %s\n', calibratedModelFile);

%% ===================== STEP 3: INVERSE KINEMATICS =====================
fprintf('\n=== Step 3: Running inverse kinematics ===\n');
ikWork = abspath(ikWork);

% Resolve the IK time range: use the settings if given, else the full trial.
% A manual endTime is clamped to the data so it can never overshoot.
if isempty(startTime), tStart = dataStart; else, tStart = max(startTime, dataStart); end
if isempty(endTime),   tEnd   = dataEnd;   else, tEnd   = min(endTime,   dataEnd);   end
fprintf('IK time range: %.3f to %.3f s\n', tStart, tEnd);

imuIK = IMUInverseKinematicsTool();
imuIK.set_model_file(calibratedModelFile);
imuIK.set_orientations_file(orientationsFile);
imuIK.set_sensor_to_opensim_rotations(sensorToOpenSim);
imuIK.set_time_range(0, tStart);
imuIK.set_time_range(1, tEnd);
imuIK.set_results_directory(ikWork);
try
    imuIK.run(visualizeTracking);
catch ME
    warning('OpenSim visualizer could not start; running IK without it.\n  (%s)', ME.message);
    imuIK.run(false);
end
% Save the IK tool setup so the simulation is self-contained / re-runnable.
ikSetupFile = abspath(fullfile(workRoot, 'IMU_IK_Setup.xml'));
imuIK.print(ikSetupFile);
cd(origDir);                     % back to the Analysis folder
fprintf('Wrote IK results to: %s\n', ikWork);

%% ===================== STEP 4: TRACKING-ERROR QUALITY CHECK =====================
% Summarise the per-IMU orientation tracking errors so you can spot a bad
% sensor at a glance. Errors in the .sto are in radians; printed in degrees.
fprintf('\n=== Step 4: Orientation tracking error summary ===\n');
warnThresholdDeg = 5;   % flag any IMU whose max error exceeds this (degrees)
errorsFile = fullfile(ikWork, ['ik_' trial '_orientations_orientationErrors.sto']);
errMean = containers.Map('KeyType','char','ValueType','double');  % per-IMU mean err (for de-drift gate)

if ~isfile(errorsFile)
    warning('Orientation errors file not found: %s', errorsFile);
else
    % Read the .sto: skip the header up to and including the 'endheader' line.
    fid = fopen(errorsFile, 'r');
    line = fgetl(fid);
    while ischar(line) && ~strcmpi(strtrim(line), 'endheader')
        line = fgetl(fid);
    end
    labels = strsplit(strtrim(fgetl(fid)), sprintf('\t'));   % column header row
    data = cell2mat(textscan(fid, repmat('%f', 1, numel(labels)), ...
                             'Delimiter', '\t', 'CollectOutput', true));
    fclose(fid);

    % Per-IMU mean / max, converted from radians to degrees (column 1 is time).
    fprintf('%-14s %10s %10s\n', 'IMU', 'mean(deg)', 'max(deg)');
    for c = 2:numel(labels)
        col = data(:, c) * (180/pi);
        errMean(labels{c}) = mean(col);          % capture for the de-drift gate
        flag = '';
        if max(col) > warnThresholdDeg
            flag = '   <-- CHECK';
        end
        fprintf('%-14s %10.3f %10.3f%s\n', labels{c}, mean(col), max(col), flag);
    end
    fprintf('(IMUs with max error > %g deg are flagged.)\n', warnThresholdDeg);
end

%% ============ STEP 5: OPTIONAL ANATOMICAL HEADING-LOCK + IK RE-RUN ============
% For heading/turn-drift trials. A knee/ankle/elbow is a hinge, so a limb's
% segments physically must share ONE heading (yaw about vertical). We therefore
% FREEZE each limb segment's heading relative to a clean base (legs -> pelvis,
% arms -> torso) at the value it had at t=0 (calibration), removing the
% differential heading DRIFT while keeping the anatomical offset and all the
% gravity-anchored tilt. The residual whole-limb heading then falls into the
% rotation DOFs (hip_rotation / arm_rot), which are discarded anyway - so
% hip_flexion, knee, ankle, arm_flex, elbow come out drift-free. IMU-only, no
% reference/gate guessing. Writes IKResults_dedrift; raw IKResults is untouched.
if applyDedrift
    fprintf('\n=== Step 5: Anatomical heading-lock + IK re-run ===\n');
    % segment -> clean reference whose heading it is locked to
    LOCK_PAIRS = { 'femur_r_imu','pelvis_imu'; 'tibia_r_imu','pelvis_imu'; 'calcn_r_imu','pelvis_imu'; ...
                   'femur_l_imu','pelvis_imu'; 'tibia_l_imu','pelvis_imu'; 'calcn_l_imu','pelvis_imu'; ...
                   'humerus_r_imu','torso_imu'; 'ulna_r_imu','torso_imu'; ...
                   'humerus_l_imu','torso_imu'; 'ulna_l_imu','torso_imu' };
    ddCells = quatCells;
    fprintf('%-14s  %-12s %12s\n', 'segment', 'locked-to', 'headingDrift(deg)');
    for p = 1:size(LOCK_PAIRS,1)
        si = find(strcmp(bodyNames, LOCK_PAIRS{p,1}), 1);
        ri = find(strcmp(bodyNames, LOCK_PAIRS{p,2}), 1);
        if isempty(si) || isempty(ri), continue; end
        % Swing-twist heading (2*atan2(qz,qw)): stable through the leg's full range
        % (unlike Tait-Bryan yaw, which gimbal-locks when a segment pitches through
        % vertical each swing). A world-Z pre-rotation adds to it exactly.
        rel   = qheadingLocal(quatCells{ri}) - qheadingLocal(quatCells{si});
        alpha = rel - rel(1);                         % differential heading DRIFT (0 at t=0)
        ddCells{si} = rotZpre(alpha, quatCells{si});  % add it back about world-up (keeps tilt)
        fprintf('%-14s  %-12s %12.1f\n', LOCK_PAIRS{p,1}, LOCK_PAIRS{p,2}, rad2deg(alpha(end)));
    end
    if true
        ddSto = fullfile(stoWork, [trial '_orientations_dedrift.sto']);
        writeQuaternionSto(ddSto, time, bodyNames, ddCells, DATA_RATE);
        ddSto = abspath(ddSto);
        ddIKWork = abspath(fullfile(workRoot, 'IKResults_dedrift'));
        if ~isfolder(ddIKWork), mkdir(ddIKWork); end
        cd(workRoot);
        imuIKdd = IMUInverseKinematicsTool();
        imuIKdd.set_model_file(calibratedModelFile);
        imuIKdd.set_orientations_file(ddSto);
        imuIKdd.set_sensor_to_opensim_rotations(sensorToOpenSim);
        imuIKdd.set_time_range(0, tStart);
        imuIKdd.set_time_range(1, tEnd);
        imuIKdd.set_results_directory(ddIKWork);
        try
            imuIKdd.run(false);
        catch ME
            warning('De-drift IK run failed: %s', ME.message);
        end
        cd(origDir);
        ddOut = fullfile(resultsRoot, 'IKResults_dedrift');
        if isfolder(ddOut), [~,~] = rmdir(ddOut, 's'); end
        copyfile(ddIKWork, ddOut);
        fprintf('De-drifted IK results -> %s\n', ddOut);

        % Before -> after per-IMU tracking error (Step-4 original vs de-drifted).
        ddErrFile = fullfile(ddOut, ['ik_' trial '_orientations_dedrift_orientationErrors.sto']);
        if isfile(ddErrFile)
            fide = fopen(ddErrFile,'r'); lne = fgetl(fide);
            while ischar(lne) && ~strcmpi(strtrim(lne),'endheader'), lne = fgetl(fide); end
            elabs = strsplit(strtrim(fgetl(fide)), sprintf('\t'));
            edata = cell2mat(textscan(fide, repmat('%f',1,numel(elabs)), 'Delimiter','\t','CollectOutput',true));
            fclose(fide);
            fprintf('\n=== Tracking error: BEFORE -> AFTER heading-lock (mean deg) ===\n');
            fprintf('%-14s %10s %10s\n','IMU','before','after');
            for c = 2:numel(elabs)
                aft = mean(edata(:,c)*180/pi,'omitnan');
                if isKey(errMean, elabs{c}), bef = errMean(elabs{c}); else, bef = NaN; end
                fprintf('%-14s %10.2f %10.2f\n', elabs{c}, bef, aft);
            end
        end
    end
end

%% ===================== COPY OUTPUTS TO RESULTS (Drive) =====================
Logger.removeFileSink();                                   % release the log file
copyfile(stoWork, fullfile(resultsRoot, 'STOFiles'));
copyfile(fullfile(workRoot, [mName '_calibrated.osim']), ...
         fullfile(resultsRoot, [mName '_calibrated.osim']));
copyfile(ikWork, fullfile(resultsRoot, 'IKResults'));
if isfile(fullfile(workRoot,'IMU_IK_Setup.xml'))
    copyfile(fullfile(workRoot,'IMU_IK_Setup.xml'), fullfile(resultsRoot,'IMU_IK_Setup.xml'));
end
if isfile(fullfile(workRoot,'opensim.log'))
    copyfile(fullfile(workRoot,'opensim.log'), fullfile(resultsRoot,'opensim.log'));
end
fprintf('Copied outputs to: %s\n', resultsRoot);

fprintf('\n=== Pipeline complete for %s ===\n', subjectName);

%% ========================================================================
%  LOCAL FUNCTIONS (custom Xsens quaternion reader)
%% ========================================================================
function tf = isLowerLimb(name)
% Lower-limb rotational coordinates whose IK cap we remove (both sides).
    tf = startsWith(name,'hip_') || startsWith(name,'knee_angle') || ...
         startsWith(name,'ankle_angle') || startsWith(name,'subtalar_angle') || ...
         startsWith(name,'mtp_angle');
end

function p = abspath(p)
% Absolute, canonical path (resolves '..'). OpenSim's native file I/O needs
% absolute paths - relative ones fail on synced/virtual drives (Google Drive).
    p = char(java.io.File(p).getCanonicalPath());
end

function h = qheadingLocal(Q)
% Heading (twist about world-up Z) from quaternion rows [q0 q1 q2 q3]=[w x y z].
    h = unwrap(2*atan2(Q(:,4), Q(:,1)));
end

function r = qmulLocal(a, b)
% Hamilton product of quaternion rows [w x y z].
    w0=a(:,1); x0=a(:,2); y0=a(:,3); z0=a(:,4);
    w1=b(:,1); x1=b(:,2); y1=b(:,3); z1=b(:,4);
    r = [w0.*w1-x0.*x1-y0.*y1-z0.*z1, ...
         w0.*x1+x0.*w1+y0.*z1-z0.*y1, ...
         w0.*y1-x0.*z1+y0.*w1+z0.*x1, ...
         w0.*z1+x0.*y1-y0.*x1+z0.*w1];
end

function Qc = rotZpre(alpha, Q)
% Pre-multiply each quaternion row of Q by a world-up (Z) rotation of alpha(t).
% A world-vertical rotation changes only heading and preserves tilt exactly.
    c = cos(alpha/2); s = sin(alpha/2);
    qz = [c, zeros(numel(alpha),2), s];
    Qc = qmulLocal(qz, Q);
end

function convertMtbToTxt(dataDir, pythonExe, converterScript, force)
% Batch-convert any Xsens .mtb in dataDir to per-IMU ASCII .txt (MT Manager
% layout: PacketCounter, Acc_X/Y/Z, Quat_q0..q3) using the Python xsensdeviceapi
% converter, so no manual MT Manager export is needed. No-op if there is no .mtb.
    mtb = dir(fullfile(dataDir, '*.mtb'));
    if isempty(mtb)
        fprintf('No .mtb in %s\n  -> using the .txt already in the folder (manual export).\n', dataDir);
        return;
    end
    if ~isfile(converterScript)
        error(['Converter script not found:\n  %s\n' ...
               'Set converterScript (top of this file) to its location.'], converterScript);
    end
    % Skip if the .txt are already up to date (newest .txt at/after newest .mtb).
    txt = dir(fullfile(dataDir, 'MT_*.txt'));
    if ~force && ~isempty(txt) && max([txt.datenum]) >= max([mtb.datenum])
        fprintf(['.txt exports already newer than the .mtb in %s\n' ...
                 '  -> skipping conversion (set forceConvert = true to redo).\n'], dataDir);
        return;
    end
    cmd = sprintf('%s "%s" "%s"', pythonExe, converterScript, abspath(dataDir));
    fprintf('\n=== Converting .mtb -> .txt (Xsens Device API) ===\n  %s\n', cmd);
    [status, out] = system(cmd);
    fprintf('%s\n', out);
    if status ~= 0
        error(['MTB -> TXT conversion failed (exit %d). Common causes:\n' ...
               '  - the .mtb is still open in MT Manager (close it and retry),\n' ...
               '  - "%s" has no ''xsensdeviceapi'' installed (install the MT SDK wheel),\n' ...
               '  - the Python launcher/version in pythonExe is not on PATH.\n' ...
               'You can still export manually from MT Manager and set convertMtb = false.'], ...
               status, pythonExe);
    end
    if isempty(dir(fullfile(dataDir, 'MT_*.txt')))
        error('Conversion reported success but produced no MT_*.txt in %s.', dataDir);
    end
    fprintf('Conversion complete.\n');
end

function map = readIMUMappings(xmlFile)
% Parse Setup/myIMUMappings.xml into a struct array of .id (sensor name
% attribute, e.g. '_00B4AB26') and .body (name_in_model, e.g. 'torso_imu').
    if ~isfile(xmlFile), error('Mappings file not found: %s', xmlFile); end
    txt = fileread(xmlFile);
    tok = regexp(txt, ...
        '<ExperimentalSensor\s+name="([^"]+)">[\s\S]*?<name_in_model>([^<]+)</name_in_model>', ...
        'tokens');
    if isempty(tok)
        error('No <ExperimentalSensor> entries found in %s', xmlFile);
    end
    map = struct('id', {}, 'body', {});
    for k = 1:numel(tok)
        map(k).id   = strtrim(tok{k}{1});
        map(k).body = strtrim(tok{k}{2});
    end
end

function fp = findSensorFile(dataDir, trial, sensorId)
% Resolve <trial><sensorId>.txt, case-insensitively (sensor IDs in the XML
% sometimes differ in case from the actual file names).
    expected = [trial sensorId '.txt'];
    cand = fullfile(dataDir, expected);
    if isfile(cand), fp = cand; return; end
    d = dir(fullfile(dataDir, '*.txt'));
    fp = '';
    for k = 1:numel(d)
        if strcmpi(d(k).name, expected)
            fp = fullfile(dataDir, d(k).name);
            return;
        end
    end
end

function q = readSensorQuat(fp)
% Read the Quat_q0..q3 columns (N x 4) from one Xsens .txt file. Skips the
% leading '//' comment block and locates the quaternion columns by name.
    fid = fopen(fp, 'r');
    if fid < 0, error('Cannot open %s', fp); end
    line = fgetl(fid);
    while ischar(line) && (isempty(strtrim(line)) || startsWith(strtrim(line), '//'))
        line = fgetl(fid);
    end
    hdr = strsplit(strtrim(line), sprintf('\t'));   % column-header row
    qi = zeros(1, 4);
    for j = 0:3
        idx = find(strcmpi(hdr, sprintf('Quat_q%d', j)), 1);
        if isempty(idx)
            fclose(fid);
            error('Column Quat_q%d not found in %s', j, fp);
        end
        qi(j+1) = idx;
    end
    C = textscan(fid, repmat('%f', 1, numel(hdr)), 'Delimiter', '\t', ...
                 'CollectOutput', true, 'EmptyValue', NaN);
    fclose(fid);
    M = C{1};
    q = M(:, qi);
end

function writeQuaternionSto(file, time, bodyNames, quatCells, rate)
% Write an OpenSim quaternion .sto (DataType=Quaternion). Each cell holds
% one quaternion as 'q0,q1,q2,q3'.
    fid = fopen(file, 'w');
    if fid < 0, error('Cannot write %s', file); end
    fprintf(fid, 'DataRate=%.6f\n', rate);
    fprintf(fid, 'DataType=Quaternion\n');
    fprintf(fid, 'version=3\n');
    fprintf(fid, 'OpenSimVersion=4.5\n');
    fprintf(fid, 'endheader\n');
    fprintf(fid, 'time');
    fprintf(fid, '\t%s', bodyNames{:});
    fprintf(fid, '\n');
    nF = numel(time);
    nS = numel(bodyNames);
    for i = 1:nF
        fprintf(fid, '%.8g', time(i));
        for s = 1:nS
            q = quatCells{s}(i, :);
            fprintf(fid, '\t%.15g,%.15g,%.15g,%.15g', q(1), q(2), q(3), q(4));
        end
        fprintf(fid, '\n');
    end
    fclose(fid);
end
