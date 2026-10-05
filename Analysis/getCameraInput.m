function local = getCameraInput(tn, root, which)
% GETCAMERAINPUT  Pull a CV-owned camera INPUT file into the IMU (Analysis) project,
% with version checking and all decisions printed to the command window.
%
%   local = getCameraInput(tn, root, which)
%     which = 'refined'   -> testN_trajectory_refined.xlsx   (from CV step 2)
%             'crossings' -> testN_crossings.xlsx             (from CV step 3)
%
% The CV project OWNS and KEEPS these files (…/obstacle-crossing-computer-vision/
% results/sessions/testN/). The IMU project keeps its own copy under
% Data/Camera CV/Test N and pulls from the CV project as needed:
%   1) no local copy             -> FETCH it from the CV project (if present).
%   2) local == CV (byte-equal)   -> use the local one, no prompt ("up to date").
%   3) local and CV copies DIFFER -> show both (size + date) and ASK whether to bring
%                                    the new CV version; copy it only if you say yes.
% Returns the LOCAL path to use, or '' if the file is available nowhere.
%
% The CV project is assumed to be the sibling folder 'obstacle-crossing-computer-vision'
% under the same parent as the IMU project.

    id = ['test' num2str(tn)];
    switch lower(which)
        case 'refined'
            fname = [id '_trajectory_refined.xlsx'];  label = sprintf('Refined trajectory (test %d)', tn);
        case 'crossings'
            fname = [id '_crossings.xlsx'];            label = sprintf('Crossings file (test %d)', tn);
        otherwise
            error('getCameraInput: ''which'' must be ''refined'' or ''crossings''.');
    end
    localFile = fullfile(root, 'Data', 'Camera CV', ['Test ' num2str(tn)], fname);
    docs      = fileparts(root);                                   % …/Documents
    cvFile    = fullfile(docs, 'obstacle-crossing-computer-vision', 'results', 'sessions', id, fname);
    local     = syncFromCV(localFile, cvFile, label);
end

function localFile = syncFromCV(localFile, cvFile, label)
    haveLocal = isfile(localFile);
    haveCV    = isfile(cvFile);

    if ~haveLocal && ~haveCV
        warning('%s: not found in the IMU project nor the CV project - generate it in the CV project first.', label);
        localFile = '';  return;
    end
    if ~haveLocal                                    % case 1: fetch from CV
        ld = fileparts(localFile);  if ~isfolder(ld), mkdir(ld); end
        copyfile(cvFile, localFile);
        fprintf('%s: no local copy - FETCHED from the CV project:\n  %s\n  -> %s\n', label, cvFile, localFile);
        return;
    end
    if ~haveCV                                       % local only (CV not reachable now)
        fprintf('%s: using the local copy (CV project copy not found):\n  %s\n', label, localFile);
        return;
    end
    if sameBytes(localFile, cvFile)                  % case 2: identical -> no prompt
        fprintf('%s: up to date (identical to the CV project).\n', label);
        return;
    end
    % case 3: they differ -> report both and ASK
    dl = dir(localFile);  dc = dir(cvFile);
    fprintf('\n*** %s: the CV project version DIFFERS from your local copy ***\n', label);
    fprintf('   current (this IMU project): %8.1f kB   modified %s\n', dl.bytes/1024, datestr(dl.datenum,'yyyy-mm-dd HH:MM'));
    fprintf('   new (CV project):           %8.1f kB   modified %s\n', dc.bytes/1024, datestr(dc.datenum,'yyyy-mm-dd HH:MM'));
    a = '';
    try, a = strtrim(input('   Bring the new CV version? (y/n): ', 's')); catch, a = ''; end
    if any(strcmpi(a, {'y','yes'}))
        copyfile(cvFile, localFile);
        fprintf('   -> UPDATED the local copy from the CV project.\n');
    else
        fprintf('   -> keeping the current local copy.\n');
    end
end

function tf = sameBytes(a, b)
% True iff the two files are byte-for-byte identical (the local copy is made by
% copyfile, so an untouched copy is byte-equal to its CV source).
    da = dir(a);  db = dir(b);
    if isempty(da) || isempty(db) || da.bytes ~= db.bytes, tf = false; return; end
    tf = isequal(readBytes(a), readBytes(b));
end

function x = readBytes(p)
    fid = fopen(p, 'r');  x = fread(fid, inf, '*uint8');  fclose(fid);
end
