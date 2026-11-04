%% =========================================================
% estimate_reaction_rate_profile.m
%
% Estimates the O2 consumption rate r of the biomass from the experimental
% DO map of the NO-FLOW interval with a PDE fit, using one constant
% diffusion coefficient D. Nothing from the abiotic test is read: D is typed
% in below.
%
% Governing equation (reaction-diffusion, 1-D along the reactor):
%
%     dC/dt = D d2C/dx2 - r
%
% r is the volumetric O2 consumption rate (zero order in DO), in mg L^-1 h^-1.
%
% METHOD. r is found for every pair of consecutive images i -> i+1:
%   * Starting profile: a smooth polynomial in x is fitted to the measured
%     profile of image i (the two edge values are pinned to the measured edge
%     strips). pdepe starts from that curve, not from a zigzag through the 15
%     data points.
%   * Boundary conditions: the measured DO of the first and last strip,
%     varying linearly in time between image i and image i+1.
%   * pdepe integrates the equation over the time between the two images.
%   * r is the single value (fminbnd) that makes the pdepe profile match the
%     measured interior strips of image i+1. The model is clipped at 0 mg/L
%     when it is compared with the data, because the mapped DO is clipped there.
%   The rate belongs to the interval from image i to image i+1 and is stored
%   at image i. The last image has no following image, so its r is empty.
%
% Everything except D comes from the experimental DO map:
%   C(x,t)           DO in 15 strips along the reactor, one profile per image
%   boundary values  the first and last strip of every image
%
% PHOTOBLEACHING. The sensor bleaches with repeated excitation: Red falls and
% Green rises with shot number, which fakes a DO change. fit_D_timevarying_BC_pdepe.m
% applies no correction itself; it reads a DO CSV that
% DO_mapping_photobleach_corrected.m already corrected. This script uses the same
% correction when it reads the repo's do_mapped files (heatmap_cal.m does not
% correct bleaching):
%   1) A saturating exponential I(n) = Iinf + (I0 - Iinf)*exp(-k n) is fitted
%      to the Green and Red curves of each sheet of logs/photobleaching.xlsx.
%   2) Each curve is normalized to its value at the shot of Image# 0, and the
%      sheets are averaged: rFactor(n) for Red, gFactor(n) for Green.
%   3) Because Red is divided by rFactor and Green is divided by gFactor, the
%      FRET/GFP ratio of an image is divided by rFactor*gFactor. The mapped DO
%      is converted back to its ratio signal with the Stern-Volmer calibration
%      (alpha, Ksv from calibration_summary_opt##.csv), corrected, and inverted
%      again, block by block, before the strips are averaged.
% With dataSource = 'csv' no correction is applied here: that CSV is assumed to
% come from DO_mapping_photobleach_corrected.m, which already removed bleaching.
%
% INPUT (choose one source below)
%   'mapped' : processed_data/do_mapped/do_mapped_t###.mat from heatmap_cal.m
%              (variable "mapped", blockwise DO map). The reactor columns are
%              cut with the same rule as biomass_occupation_bulkDO_cal.m and
%              split into 15 strips along x; each strip averages all rows.
%   'csv'    : wide DO profile CSV from the DO mapping script (X_mm, then
%              one DO_t<n>_<m>min column per frame).
%   logs/imaging_timestamp.xlsx   (repo log; Image#, Datetime) gives the
%              true time of every image.
%   logs/photobleaching.xlsx, logs/calibration_summary*.csv   (only for the
%              bleaching correction of the 'mapped' source; needs the
%              Optimization Toolbox for fmincon)
%
% OUTPUT (nothing is saved to disk; everything is shown on screen)
%   Figure 1  r vs time
%   Figure 2  r vs mean DO
%   Figure 3  pdepe fit vs measured profiles
%   Workspace variable Tout: one row per image number with r, fit error, mean DO
%   (type  Tout  to look at it, or  P  and  S  for the raw fit and data).
%
% Notes
%   * Run this from the analysis_scripts folder (paths are relative to it,
%     as in the other repo scripts).
%   * D must be on the TRUE time base (m^2/s with real seconds). A D fitted
%     on the CSV minute labels (1 min per frame) must be divided by the true
%     minutes per frame first.
%   * Strips are bins of the 15 mm reactor; the domain is the 14 mm between
%     the two edge-strip centers.
%   * Each r comes from only two images, so it is noisier than a rate fitted
%     over many images. Smooth r(t) afterwards if you need a steadier curve.
%   * A zero-order sink can push the model below 0 mg/L in anoxic strips. The
%     comparison clips it at 0, but rates in intervals with many anoxic strips
%     are biased low.
%% =========================================================

clear; clc; close all;

%% =========================================================
%  USER SETTINGS  <- edit here
%% =========================================================

% --- Diffusion coefficient (one constant value for every image) ---
D_m2s = 4.99e-9;          % <-- m^2/s on the TRUE time base

% --- No-flow interval to analyze ---
imageRange = [12 57];          % <-- [first last] Image# of the no-flow interval
                          %     (Image# numbering of imaging_timestamp.xlsx); [] = all
                          %     Only these images enter the fits.

% --- Where the experimental DO map lives ---
dataSource   = 'mapped';  % 'mapped' or 'csv'
mappedDir    = fullfile('..', 'processed_data', 'do_mapped');
imageOffset  = 0;         % Image# = (number in do_mapped_t###.mat) + imageOffset
csvFile      = 'DO_profile_timeseries_biotic.csv';
firstImageCsv = 0;        % Image# of the FIRST column of the CSV
nStrips      = 15;        % strips along the reactor ('mapped' source)
reactorLength_mm = 15;    % reactor length ('mapped' source)

% --- Photobleaching correction (applies to dataSource = 'mapped' only) ---
bleachCorrect = true;     % false: use the mapped DO as it is
bleachFile    = fullfile('..', 'logs', 'photobleaching.xlsx');
bleachSheets  = {'20250130-sample231', '20250130-sample201'};   % fitted separately, then averaged
calibDir      = fullfile('..', 'logs');       % folder holding calibration_summary*.csv
shotOfImage0  = 1;        % shot number of Image# 0 in the bleaching calibration; the
                          % shot of Image# i is shotOfImage0 + i (one shot per image)

% --- Time of every image ---
stampFile      = fullfile('..', 'logs', 'imaging_timestamp.xlsx');
dtFallback_min = NaN;     % minutes between images, used only if there is no stampFile

% --- Numerics ---
rLimit_mgLh = 5;     % mg/L/h; search bound for r (negative allowed)
icPolyDeg   = 2;      % degree of the smooth polynomial fitted to the starting profile
                      % (edge values pinned to the measured edge strips); lower = smoother

% --- Fit check figure (pdepe fit over the measured profiles) ---
fitPlotImages = [20 40 50];   % Image# of the intervals to show (start image); [] = 6 evenly spaced
fitPlotCols   = 5;    % panels per row

%% =========================================================
%  LOAD THE EXPERIMENTAL DO MAP
%% =========================================================
switch lower(dataSource)
    case 'mapped'
        bleachOpts = [];
        if bleachCorrect
            bleachOpts = struct('file', bleachFile, 'sheets', {bleachSheets}, ...
                                'calibDir', calibDir, 'shotOfImage0', shotOfImage0);
        end
        S = load_from_mapped(mappedDir, imageOffset, imageRange, nStrips, reactorLength_mm, bleachOpts);
    case 'csv'
        S = load_from_csv(csvFile, firstImageCsv, imageRange);
        if bleachCorrect
            fprintf('CSV source: assumed already photobleach-corrected by the DO mapping script; no correction applied here.\n');
        end
    otherwise
        error('dataSource must be ''mapped'' or ''csv''.');
end
[S.t_true_min, S.timeSrc] = image_times(S.image, stampFile, dtFallback_min);

nT = numel(S.image);
if nT < 2
    error('Need at least 2 images; found %d. Widen imageRange.', nT);
end
fprintf('Analyzing Image# %d..%d: %d strips x %d images, %.1f to %.1f min (time from %s)\n', ...
    S.image(1), S.image(end), size(S.C, 1), nT, S.t_true_min(1), S.t_true_min(end), S.timeSrc);
fprintf('D = %.3e m^2/s (O2 in water at 25 C is about 2.1e-9 m^2/s)\n', D_m2s);

%% =========================================================
%  PDE FIT, ONE r PER INTERVAL BETWEEN CONSECUTIVE IMAGES
%% =========================================================
fprintf('PDE fit ...\n');
P = fit_intervals(S, D_m2s, rLimit_mgLh, icPolyDeg);

fprintf('\nMedian r (PDE fit): %.3f mg/L/h\n', median(P.r, 'omitnan'));

%% =========================================================
%  RESULT TABLE (kept in the workspace, not saved)
%% =========================================================
xBulk = (S.X_mm - S.X_mm(1)) * 1e-3;
Cbar  = (trapz(xBulk, S.C, 1) / (xBulk(end) - xBulk(1)))';     % mean DO over the domain, mg/L

Tout = table(S.image, S.t_true_min, Cbar, P.r, P.rmse, P.Cmean, S.rFactor, S.gFactor, ...
    'VariableNames', {'Image', 'Time_min', 'DO_bulk_mgL', 'r_mgLh', 'fit_rmse_mgL', 'DO_interval_mean_mgL', ...
                      'Bleach_Red_factor', 'Bleach_Green_factor'});

%% =========================================================
%  FIGURE 1: r(t)
%% =========================================================
clrDO = [0.004 0.400 0.369];     % teal (matches the manuscript figures)
clrR  = [0.75 0.10 0.10];

t_h = S.t_true_min / 60;

fig1 = figure('Color', 'w', 'Units', 'inches', 'Position', [1 1 6 3.8]);
ax1 = axes(fig1); hold(ax1, 'on');
plot(ax1, t_h, P.r, '-', 'Color', clrR, 'LineWidth', 2.0);
yline(ax1, 0, '-', 'Color', [0.2 0.2 0.2], 'LineWidth', 0.5);
xlabel(ax1, 'Experiment time (h)', 'FontSize', 10, 'FontWeight', 'bold');
ylabel(ax1, 'O_2 consumption rate r (mg L^{-1} h^{-1})', 'FontSize', 10, 'FontWeight', 'bold');
grid(ax1, 'on'); box(ax1, 'on');
ax1.GridAlpha = 0.15; ax1.LineWidth = 0.8; ax1.FontSize = 9; ax1.FontWeight = 'bold';

%% =========================================================
%  FIGURE 2: r vs mean DO
%% =========================================================
fig2 = figure('Color', 'w', 'Units', 'inches', 'Position', [1 1 5 3.8]);
ax2 = axes(fig2); hold(ax2, 'on');
scatter(ax2, P.Cmean, P.r, 16, t_h, 'filled');
cb2 = colorbar(ax2); cb2.Label.String = 'Time (h)';
colormap(ax2, parula);
xlabel(ax2, 'Mean interior DO of the interval (mg L^{-1})', 'FontSize', 10, 'FontWeight', 'bold');
ylabel(ax2, 'r (mg L^{-1} h^{-1})', 'FontSize', 10, 'FontWeight', 'bold');
grid(ax2, 'on'); box(ax2, 'on');
ax2.GridAlpha = 0.15; ax2.FontSize = 9; ax2.FontWeight = 'bold';

%% =========================================================
%  FIGURE 3: pdepe FIT OVER THE MEASURED DO PROFILES
%  Each panel is one interval (image i -> image i+1).
%  Dots = measured profiles, lines = smooth curves: the polynomial starting
%  profile (dark) and the pdepe profile at the end of the interval (light).
%% =========================================================
okI = find(isfinite(P.r));
if isempty(fitPlotImages)
    kSel = okI(unique(round(linspace(1, numel(okI), min(6, numel(okI))))));
else
    kSel = zeros(1, numel(fitPlotImages));
    for q = 1:numel(fitPlotImages)
        [~, pos] = min(abs(S.image(okI) - fitPlotImages(q)));   % nearest fitted interval
        kSel(q)  = okI(pos);
    end
    kSel = unique(kSel, 'stable');
end
nP = numel(kSel);  nc = min(fitPlotCols, nP);  nr = ceil(nP / nc);

xS_m  = (S.X_mm - S.X_mm(1)) * 1e-3;
t_sec = S.t_true_min * 60;
XQ_mm = linspace(S.X_mm(1), S.X_mm(end), 300)';        % dense axis for drawing smooth curves
colStart = clrDO;
colEnd   = [0.55 0.85 0.80];

fig3 = figure('Color', 'w', 'Units', 'inches', 'Position', [1 1 3.0*nc + 0.6, 2.5*nr + 0.8]);
for q = 1:nP
    k  = kSel(q);
    Cm = interval_solution(P.r(k), xS_m, t_sec(k:k+1), S.C(:, k), S.C(:, k+1), D_m2s, icPolyDeg);   % nX x 2
    ax = subplot(nr, nc, q); hold(ax, 'on');
    plot(ax, S.X_mm, S.C(:, k),   'o', 'Color', colStart, 'MarkerFaceColor', colStart, 'MarkerSize', 3.5);
    plot(ax, S.X_mm, S.C(:, k+1), 'o', 'Color', colEnd,   'MarkerFaceColor', colEnd,   'MarkerSize', 3.5);
    plot(ax, XQ_mm, interp1(S.X_mm, Cm(:, 1), XQ_mm, 'pchip'), '-', 'Color', colStart, 'LineWidth', 1.4);
    plot(ax, XQ_mm, interp1(S.X_mm, Cm(:, 2), XQ_mm, 'pchip'), '-', 'Color', colEnd,   'LineWidth', 1.4);
    title(ax, sprintf('Image %d to %d,  r = %.2f mg L^{-1} h^{-1}', S.image(k), S.image(k+1), P.r(k)), ...
        'FontSize', 8, 'FontWeight', 'bold');
    grid(ax, 'on'); box(ax, 'on');
    ax.GridAlpha = 0.15; ax.FontSize = 8; ax.FontWeight = 'bold';
    if q > nP - nc
        xlabel(ax, 'Distance (mm)', 'FontSize', 9, 'FontWeight', 'bold');
    end
    if mod(q - 1, nc) == 0
        ylabel(ax, 'DO (mg L^{-1})', 'FontSize', 9, 'FontWeight', 'bold');
    end
    if q == 1
        h1 = plot(ax, NaN, NaN, 'o', 'Color', [0.3 0.3 0.3], 'MarkerFaceColor', [0.3 0.3 0.3], 'MarkerSize', 3.5);
        h2 = plot(ax, NaN, NaN, '-', 'Color', [0.3 0.3 0.3], 'LineWidth', 1.4);
        legend(ax, [h1 h2], {'measured', 'pdepe fit'}, 'Location', 'best', 'Box', 'off', 'FontSize', 7);
    end
end
sgtitle(fig3, 'pdepe fit vs measured DO profiles (dark = start image, light = next image)', ...
    'FontSize', 9, 'FontWeight', 'bold');
fprintf('Done. Results are in the workspace variables Tout, P and S; nothing was saved.\n');

%% =========================================================
%  LOCAL FUNCTIONS
%% =========================================================
function S = load_from_mapped(mappedDir, imageOffset, imageRange, nStrips, L_mm, bleachOpts)
% Reads do_mapped_t###.mat (variable "mapped"), removes photobleaching
% (if bleachOpts is not empty), cuts the reactor columns with the repo rule
% (reactor_cols), and averages the map into nStrips strips along x. Only the
% images inside imageRange are loaded.
    f = dir(fullfile(mappedDir, 'do_mapped_t*.mat'));
    if isempty(f)
        error('No do_mapped_t*.mat files in %s. Run heatmap_cal.m first or use dataSource = ''csv''.', mappedDir);
    end
    nums = arrayfun(@(q) sscanf(q.name, 'do_mapped_t%d.mat'), f);
    [nums, o] = sort(nums);  f = f(o);
    img = nums(:) + imageOffset;
    keep = in_range(img, imageRange);
    if ~any(keep)
        error('No do_mapped files with Image# inside [%d %d] (available %d..%d).', ...
            imageRange(1), imageRange(2), img(1), img(end));
    end
    f = f(keep);  img = img(keep);

    rF = nan(numel(f), 1);  gF = nan(numel(f), 1);
    if ~isempty(bleachOpts)
        shots = bleachOpts.shotOfImage0 + img(:);       % shot number of each image
        [rF, gF] = bleach_factors(shots, bleachOpts.file, bleachOpts.sheets, bleachOpts.shotOfImage0);
        cf = dir(fullfile(bleachOpts.calibDir, 'calibration_summary*.csv'));
        if isempty(cf)
            error('No calibration_summary*.csv in %s (needed for the bleaching correction).', bleachOpts.calibDir);
        end
        Tc = readtable(fullfile(cf(1).folder, cf(1).name));
        alphaS = Tc.alpha_shared(1);  KsvS = Tc.Ksv_shared(1);
        fprintf('Photobleaching: Red factor %.3f -> %.3f, Green factor %.3f -> %.3f (first -> last image)\n', ...
            rF(1), rF(end), gF(1), gF(end));
    end

    C = nan(nStrips, numel(f));
    for j = 1:numel(f)
        m = load(fullfile(mappedDir, f(j).name), 'mapped');
        M = double(m.mapped);
        if ~isempty(bleachOpts)
            M = remove_bleaching(M, rF(j) * gF(j), alphaS, KsvS);
        end
        [cs, ce] = reactor_cols(size(M, 2), size(M, 1));
        R = M(:, cs:ce);
        edges = round(linspace(1, size(R, 2) + 1, nStrips + 1));
        for k = 1:nStrips
            blk = R(:, edges(k):edges(k+1) - 1);
            C(k, j) = mean(blk(:), 'omitnan');
        end
    end
    C = fill_missing_profile(C, mappedDir);
    S = struct('X_mm', ((1:nStrips)' - 0.5) * L_mm / nStrips, 'C', C, 'image', img(:), ...
               'rFactor', rF, 'gFactor', gF);
end

function M = remove_bleaching(M, f, alpha, Ksv)
% M: mapped DO of one image. f = rFactor*gFactor of that image.
% heatmap_cal.m inverts B = alpha + (1-alpha)/(1 + Ksv*C), where B is the
% FRET/GFP ratio signal. Rebuild B, divide by f (bleaching lowers Red and
% raises Green, so the measured ratio is off by rFactor*gFactor), and invert again.
    B  = alpha + (1 - alpha) ./ (1 + Ksv .* M);
    Bc = B ./ f;
    M  = ((1 - alpha) ./ (Bc - alpha) - 1) ./ Ksv;
    M((Bc - alpha) <= 0 | ~isfinite(M)) = NaN;
    M(M < 0) = 0;                           % same clipping as heatmap_cal.m
end

function [rF, gF] = bleach_factors(shots, file, sheets, n0)
% Fits the bleaching curves of every sheet, normalizes each to its value at
% shot n0, and averages the sheets. Returns column vectors, one value per shot.
    nS = numel(sheets);
    rAll = nan(nS, numel(shots));  gAll = rAll;
    for iS = 1:nS
        raw = readmatrix(file, 'Sheet', sheets{iS}, 'Range', 'A3:C100000');
        raw = raw(~isnan(raw(:, 1)), :);
        [I0G, IinfG, kG, R2G] = fit_bleach_curve(raw(:, 1), raw(:, 2));   % Green
        [I0R, IinfR, kR, R2R] = fit_bleach_curve(raw(:, 1), raw(:, 3));   % Red
        fprintf('Photobleaching fit [%s]: Green R^2=%.4f, Red R^2=%.4f\n', sheets{iS}, R2G, R2R);
        if max(shots) > max(raw(:, 1))
            warning('%s covers %d shots; extrapolating the fit to shot %d.', sheets{iS}, max(raw(:, 1)), max(shots));
        end
        gAll(iS, :) = (bleach_model(shots(:)', I0G, IinfG, kG) / bleach_model(n0, I0G, IinfG, kG));
        rAll(iS, :) = (bleach_model(shots(:)', I0R, IinfR, kR) / bleach_model(n0, I0R, IinfR, kR));
    end
    gF = mean(gAll, 1)';
    rF = mean(rAll, 1)';
end

function I = bleach_model(n, I0, Iinf, k)
% Saturating-exponential photobleaching model (decaying or rising channel).
    I = Iinf + (I0 - Iinf) .* exp(-k .* n);
end

function [I0, Iinf, k, R2] = fit_bleach_curve(n, I)
% Fits I(n) = Iinf + (I0 - Iinf) * exp(-k*n) to per-shot intensity data.
    n = n(:); I = I(:);
    obj = @(p) sum( (bleach_model(n, p(1), p(2), p(3)) - I).^2 );
    p0 = [I(1), I(end), 0.01];
    lb = [0, 0, 1e-8];
    ub = [2*max(I), 2*max(I), 10];
    opts = optimoptions('fmincon', 'Display', 'off', 'Algorithm', 'interior-point');
    p = fmincon(obj, p0, [], [], [], [], lb, ub, [], opts);
    I0 = p(1); Iinf = p(2); k = p(3);
    Ihat = bleach_model(n, I0, Iinf, k);
    R2 = 1 - sum((I - Ihat).^2) / sum((I - mean(I)).^2);
end

function [cs, ce] = reactor_cols(W, H)
% Same rule as biomass_occupation_bulkDO_cal.m: reactor length = 1.5 x image height.
    reactor_L = round(1.5 * H);
    center = round(W / 2);
    cs = max(1, center - round(reactor_L / 2));
    ce = min(W, center + round(reactor_L / 2));
end

function S = load_from_csv(csvFile, firstImage, imageRange)
% Reads a wide DO profile CSV (X_mm, DO_t<n>_<m>min columns).
    T  = readtable(csvFile, 'TextType', 'string');
    vn = T.Properties.VariableNames;
    tIdx = find(startsWith(vn, 'DO_t'));
    nT = numel(tIdx);
    t_label = nan(nT, 1);
    for j = 1:nT
        tok = regexp(vn{tIdx(j)}, '^DO_t(\d+)_(\d+)min$', 'tokens', 'once');
        if isempty(tok)
            error('Could not parse time from column name: %s', vn{tIdx(j)});
        end
        t_label(j) = str2double([tok{1} '.' tok{2}]);
    end
    [~, ord] = sort(t_label);
    C = table2array(T(:, tIdx(ord)));
    img = firstImage + (0:nT-1)';
    keep = in_range(img, imageRange);
    if ~any(keep)
        error('No CSV columns with Image# inside [%d %d] (available %d..%d).', ...
            imageRange(1), imageRange(2), img(1), img(end));
    end
    C = fill_missing_profile(C(:, keep), csvFile);
    X_mm = T.X_mm;
    if max(abs(diff(X_mm) - mean(diff(X_mm)))) > 0.01 * mean(diff(X_mm))
        warning('Strip spacing is not uniform; the PDE grid assumes the measured positions.');
    end
    S = struct('X_mm', X_mm, 'C', C, 'image', img(keep), ...
               'rFactor', nan(nnz(keep), 1), 'gFactor', nan(nnz(keep), 1));
end

function keep = in_range(img, imageRange)
    if isempty(imageRange)
        keep = true(size(img));
    else
        if numel(imageRange) ~= 2 || imageRange(2) <= imageRange(1)
            error('imageRange must be [first last] with last > first.');
        end
        keep = img >= imageRange(1) & img <= imageRange(2);
    end
end

function C = fill_missing_profile(C, src)
    if any(~isfinite(C(:)))
        warning('%s: %d non-finite DO values filled by interpolation in time.', src, sum(~isfinite(C(:))));
        C = fillmissing(C, 'linear', 2, 'EndValues', 'nearest');
    end
end

function [t_min, src] = image_times(img, stampFile, dtFallback_min)
% True time of every image in minutes since the experiment start (Image# 0).
    if ~isempty(stampFile) && isfile(stampFile)
        Ts  = readtable(stampFile);
        im  = Ts{:, 1};
        dtv = Ts{:, 2};
        if ~isdatetime(dtv)
            dtv = datetime(string(dtv), 'InputFormat', 'MM/dd/yyyy hh:mm:ss a');
        end
        ok = isfinite(im) & ~isnat(dtv);
        im = im(ok);  dtv = dtv(ok);
        [im, o] = sort(im);  dtv = dtv(o);
        [tf, loc] = ismember(img, im);
        if ~all(tf)
            error('%s lacks Image# %s needed for the analyzed images.', ...
                stampFile, mat2str(img(~tf)'));
        end
        t_min = minutes(dtv(loc) - dtv(1));
        src = 'imaging_timestamp.xlsx';
    elseif isfinite(dtFallback_min)
        t_min = img(:) * dtFallback_min;
        src = 'a fixed interval';
    else
        error('No timestamp file at "%s" and no dtFallback_min. Set one of them.', stampFile);
    end
    t_min = t_min(:);
    if any(diff(t_min) <= 0)
        error('Image times are not strictly increasing.');
    end
end

function Cf = smooth_profile(xS, C, deg, xF)
% Smooth polynomial fit of one profile, evaluated on xF. The first and last
% values are pinned to the measured edge strips (they are the boundary
% conditions): C(z) = base(z) + z*(1-z)*q(z), z = scaled position, q a
% polynomial of degree deg-2 fitted to the interior strips.
    xS = xS(:);  C = C(:);
    L  = xS(end) - xS(1);
    z  = (xS - xS(1)) / L;
    zF = (xF(:) - xS(1)) / L;
    base = @(zz) C(1) + (C(end) - C(1)) * zz;
    k  = 0:max(deg - 2, 0);
    zi = z(2:end-1);
    A  = (zi .* (1 - zi)) .* (zi .^ k);
    a  = A \ (C(2:end-1) - base(zi));
    Cf = base(zF) + ((zF .* (1 - zF)) .* (zF .^ k)) * a;
    Cf = max(Cf, 0);
end

function P = fit_intervals(S, D, rLimit_mgLh, icPolyDeg)
% One r per pair of consecutive images (i -> i+1), fitted with pdepe.
    x  = (S.X_mm - S.X_mm(1)) * 1e-3;
    t_s = S.t_true_min * 60;
    nT = size(S.C, 2);

    P.r     = nan(nT, 1);
    P.rmse  = nan(nT, 1);
    P.Cmean = nan(nT, 1);
    opts = optimset('TolX', 1e-3, 'Display', 'off');

    for k = 1:nT-1
        C0 = S.C(:, k);
        C1 = S.C(:, k+1);
        tw = t_s(k:k+1);
        target = C1(2:end-1);               % measured interior at the end of the interval

        obj = @(p) interval_sse(p, x, tw, C0, C1, D, icPolyDeg, target);
        [p, sse] = fminbnd(obj, -rLimit_mgLh, rLimit_mgLh, opts);

        P.r(k)     = p;
        P.rmse(k)  = sqrt(sse / numel(target));
        P.Cmean(k) = mean([C0(2:end-1); C1(2:end-1)]);

        if mod(k, 25) == 0 || k == nT-1
            fprintf('  interval %d of %d\n', k, nT-1);
        end
    end
end

function Cm = interval_solution(p_mgLh, x, tw, C0, C1, D, icPolyDeg)
% Forward solve of dC/dt = D d2C/dx2 - V between two images. Returns the
% profile at the start (the smooth polynomial) and at the end (nX x 2).
% Start profile: smooth polynomial through image 1 with the edge values pinned.
% Boundary conditions: measured edge values, linear in time between the images.
% pdepe needs at least three time points, so the midpoint is added.
    V  = p_mgLh / 3600;                     % mg L^-1 s^-1
    t3 = [tw(1), 0.5 * (tw(1) + tw(2)), tw(2)];
    IC = smooth_profile(x, C0, icPolyDeg, x);
    CLf = @(tq) C0(1)   + (C1(1)   - C0(1))   * (tq - tw(1)) / (tw(2) - tw(1));
    CRf = @(tq) C0(end) + (C1(end) - C0(end)) * (tq - tw(1)) / (tw(2) - tw(1));
    pdefun = @(xx, tt, u, dudx) deal(1, D * dudx, -V);
    icfun  = @(xx) interp1(x, IC, xx, 'linear', 'extrap');
    bcfun  = @(xl, ul, xr, ur, tt) deal(ul - CLf(tt), 0, ur - CRf(tt), 0);
    sol = pdepe(0, pdefun, icfun, bcfun, x, t3);
    Cm  = [IC(:), squeeze(sol(3, :, 1))'];  % nX x 2
end

function sse = interval_sse(p_mgLh, x, tw, C0, C1, D, icPolyDeg, target)
% Squared misfit between the pdepe profile at the end of the interval and
% the measured interior strips. The model is clipped at 0 like the data.
    Cm  = interval_solution(p_mgLh, x, tw, C0, C1, D, icPolyDeg);
    res = max(Cm(2:end-1, 2), 0) - target;
    sse = sum(res(:).^2);
end