function T = signNormTools()
% SIGNNORMTOOLS  Data-driven left/right + per-trial SIGN normalization.
%
%   T = signNormTools();  returns function handles:
%       TPL = T.build(tests, root [,segSys])   build reference sign templates
%       Sg  = T.apply(Sg, S5, TPL [,segSys])   flip a loaded Seg struct to match
%
% WHY: the OpenSim IK joint angles and (occasionally) the Dot segment tilts come
% out with inconsistent signs between the two legs and between trials/participants
% (a rotated sensor-to-body calibration flips a limb's angle). This breaks any
% DIRECTIONAL peak (flexion vs extension) that pools sides or participants. ROM
% (max-min) is sign-invariant, so it is unaffected; only directional peaks need this.
%
% HOW: for each target signal, collect every participant x side mean LEVEL-WALK
% stride (referenced to begin-ZVP), iteratively sign-align them by correlation to a
% common template, then fix the absolute polarity so the primary direction (anchor)
% dominates with the expected sign. apply() flips each side of one participant whose
% level-walk curve correlates negatively with that template.
%
% SCOPE: only signals whose sign is internally consistent within a trial are
% listed (hip joint + the three Dot segments). Knee/ankle joints flip sign between
% walking and crossing (angle wrapping) and are deliberately NOT normalized here;
% their directional peaks are not reported.
    T.build = @buildSignTemplates;
    T.apply = @applySignNorm;
end

function DEF = targetSignals()
% {signal, kind, anchor-direction}. anchor = which extremum should dominate after
% normalization, matching the primary peak in PEAKDEF / the def figures.
    DEF = { 'hip_flexion','Joint','min';   % flexion dominant, negative
            'Thigh','Seg','max';           % forward tilt dominant, positive
            'Shank','Seg','min';           % backward (heel-up) dominant, negative
            'Foot','Seg','min' };          % toe-down dominant, negative
end

function TPL = buildSignTemplates(tests, root, segSys)
    if nargin < 3 || isempty(segSys), segSys = 'Dot'; end
    DEF = targetSignals();
    TPL = struct('sig',{},'kind',{},'anchor',{},'curve',{});
    for i = 1:size(DEF,1)
        sig = DEF{i,1};  kind = DEF{i,2};  anchor = DEF{i,3};
        C = [];
        for tn = tests
            [Sg, S5] = loadSeg(root, tn);  if isempty(Sg), continue; end
            for sd = {'L','R'}
                c = lwMeanCurve(Sg, S5, sig, kind, sd{1}, segSys);
                if ~all(isnan(c)), C = [C, c(:)]; end %#ok<AGROW>
            end
        end
        tpl = setPolarity(alignSigns(C), anchor);
        TPL(end+1) = struct('sig',sig,'kind',kind,'anchor',anchor,'curve',tpl); %#ok<AGROW>
    end
end

function Sg = applySignNorm(Sg, S5, TPL, segSys)
    if nargin < 4 || isempty(segSys), segSys = 'Dot'; end
    for i = 1:numel(TPL)
        if isempty(TPL(i).curve), continue; end
        for sd = {'L','R'}
            s = sd{1};
            k = sigIndex(Sg, TPL(i).sig, TPL(i).kind, s, segSys);  if isempty(k), continue; end
            c = lwCurveFromIdx(Sg, S5, k, s);
            if all(isnan(c)), continue; end
            if localcorr(c, TPL(i).curve) < 0
                Sg.signal(k).strides = -Sg.signal(k).strides;   % ROM is sign-invariant; this only flips direction
            end
        end
    end
end

% -------------------- helpers --------------------
function [Sg, S5] = loadSeg(root, tn)
    Sg = [];  S5 = [];
    b = fullfile(root,'Results','Parameters Output',['Test ' num2str(tn)]);
    f = fullfile(b, sprintf('SegmentedParams_Test%d.mat', tn));
    if ~isfile(f), return; end
    d = load(f);  Sg = d.Seg;
    g = load(fullfile(b, sprintf('SegTrajectories_WithCamera_Test%d.mat', tn)));
    fn = fieldnames(g);  S5 = g.(fn{1});
end

function k = sigIndex(Sg, sig, kind, s, segSys)
    if strcmp(kind,'Joint')
        lbl = sprintf('Joint: %s_%s', sig, lower(s));
    else
        if s=='R'||s=='r', w = 'Right'; else, w = 'Left'; end
        lbl = sprintf('IMU: %s %s (%s) X', w, sig, segSys);
    end
    k = find(strcmp({Sg.signal.label}, lbl), 1);
end

function c = lwMeanCurve(Sg, S5, sig, kind, s, segSys)
    k = sigIndex(Sg, sig, kind, s, segSys);
    if isempty(k), c = nan(Sg.nseg,1); return; end
    c = lwCurveFromIdx(Sg, S5, k, s);
end

function c = lwCurveFromIdx(Sg, S5, k, s)
% Mean LEVEL-WALK stride curve for signal index k, begin-ZVP referenced.
    Y = Sg.signal(k).strides;
    if s=='R'||s=='r', T = S5.camera.terrainR; else, T = S5.camera.terrainL; end
    sel = false(1, size(Y,2));
    for q = 1:min(size(Y,2), numel(T))
        if ~isempty(T{q}) && strcmpi(T{q}, 'Level_Walk'), sel(q) = true; end
    end
    if ~any(sel), c = nan(size(Y,1),1); return; end
    m = mean(Y(:,sel), 2, 'omitnan');
    c = m - median(m(1:min(4,numel(m))), 'omitnan');
end

function tpl = alignSigns(C)
    if isempty(C), tpl = []; return; end
    tpl = C(:,1);
    for pass = 1:3
        for j = 1:size(C,2)
            if localcorr(C(:,j), tpl) < 0, C(:,j) = -C(:,j); end
        end
        tpl = mean(C, 2, 'omitnan');
    end
end

function tpl = setPolarity(tpl, anchor)
    if isempty(tpl), return; end
    up = abs(max(tpl));  dn = abs(min(tpl));
    if strcmp(anchor,'min')
        if up > dn, tpl = -tpl; end   % want the dominant excursion negative
    else
        if dn > up, tpl = -tpl; end   % want the dominant excursion positive
    end
end

function r = localcorr(a, b)
    a = a(:);  b = b(:);  n = min(numel(a), numel(b));  a = a(1:n);  b = b(1:n);
    g = ~isnan(a) & ~isnan(b);  a = a(g);  b = b(g);
    if numel(a) < 4, r = 0; return; end
    a = a - mean(a);  b = b - mean(b);
    d = sqrt(sum(a.^2) * sum(b.^2));
    if d == 0, r = 0; else, r = sum(a.*b) / d; end
end
