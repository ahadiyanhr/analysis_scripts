%% =========================================================================
%  perm_calc_new.m
%  Computes and plots smoothed, NORMALIZED bulk permeability (k / k_peak)
%  vs. time for the three main experiments (cP, cQhigh, cQlow).
%
%  Darcy's Law:  k = (Q * mu * L) / (A * dP)
%
%  Units:  Q [uL/min] -> [m3/s]
%          dP [mbar]  -> [Pa]
%          k          -> [m2]  (normalized to k / k_peak, dimensionless)
%
%  Workflow
%    1. Search every folder under ROOT_PATH; a folder whose NAME contains
%       "cP", "cQhigh" or "cQlow" is one experiment (legend label = tag).
%    2. Inside each experiment folder (any depth) read:
%         *__ob1_pressures / *__reader_pressures  .txt  -> pressure
%         *__ob1_flowrate  / *__reader_flowrate   .txt  -> flowrate
%         *offset*.xlsx                                 -> sensor offsets
%    3. Starting point of each curve = highest k in the early part of the
%       run (first PEAK_SEARCH_H hours). k is normalized by that value, so
%       every curve starts at k/k_peak = 1.
%    4. All curves end when the FIRST experiment ends.
%
%  Style follows plot_for_manuscripts_1panels.m (8" x 2.5", bold 9-pt axes,
%  10-pt bold labels, light grid, box on, PDF vector + TIF 300 dpi).
% =========================================================================
clc; clear; close all;

%% ── USER SETTINGS ← edit here ────────────────────────────────────────────
% FIX: root folder that holds all experiment folders (searched recursively)
ROOT_PATH = pwd;

SMOOTH_WINDOW = 2000;          % movmean window [samples] (1 Hz → ~33 min)

% FIX: minimum ΔP (after offset) treated as measurable. Below this, k is
% set to NaN, so noise near ΔP ≈ 0 cannot become the "peak".
% Sensor step ~0.1 mbar, noise ~0.17 mbar → 1 mbar ≈ 6× the noise.
DP_MIN_MBAR = 0.1;

% FIX: the peak (starting point) is searched only in this early window,
% so a late spike (e.g. after sloughing) cannot become the start point.
PEAK_SEARCH_H = 12;            % [h] from the start of each experiment

% FIX: false → x-axis is experiment time (matches the other manuscript
% panels); true → each curve is re-zeroed at its own peak.
ZERO_AT_PEAK = true;

% Reduction reference line (k/k_peak = 1/N). Set to [] to hide it.
REDUCTION_FACTOR = 10;

% FIX: y-axis cutoff. Values below Y_FLOOR are drawn ON the bottom spine
% and the bottom tick reads "<10^{-4}".
Y_FLOOR = 1e-4;
Y_TOP   = 1;

% Device geometry
W  = 1e-2;                   % channel width  [m]   (1 cm)
H  = 30e-6;                  % channel height [m]   (30 µm)
L  = 1.5e-2;                 % channel length [m]   (1.5 cm)
A  = W * H;                  % cross-section  [m2]

% Fluid
MU = 8.9e-4;                 % dynamic viscosity of water [Pa·s]

% Unit conversions
UL_PER_MIN_TO_M3_PER_S = 1e-9 / 60;   % µL/min  → m³/s
MBAR_TO_PA             = 100;         % mbar    → Pa

% FIX: experiment tags, listed in ORDER OF IMPORTANCE (cP > cQhigh > cQlow).
%   col 1: tag key | col 2: regex matched against the folder name
%   col 3: legend label (TeX) | col 4: color | col 5: line style | col 6: width
%
% Color logic (consistent with plot_for_manuscripts_1panels.m):
%   cP     → steel blue (the cP color in the 1-panel figure), solid, thickest
%   cQhigh → crimson (the cQ color in the 1-panel figure), dashed
%   cQlow  → light crimson, dotted, thinnest — same family as cQhigh so the
%            two cQ runs read as a pair, but visually subordinate
% Line style + width also separate the curves in grayscale print.
TAGS = {
    'cP',     '(?<![A-Za-z])cP(?![a-z])',     'cP',        [0.129 0.400 0.675], '-',  1.6; % blue
    'cQhigh', '(?<![A-Za-z])cQ[_\-\s]?high',  'cQ_{high}', [0.851 0.373 0.008], '-', 1.6;   % burnt orange
    'cQlow',  '(?<![A-Za-z])cQ[_\-\s]?low',   'cQ_{low}',  [0.40 0.40 0.40], '-',  1.6;   % neutral dark gray
};

% Figure (same size as plot_for_manuscripts_1panels.m)
figW_in = 8;
figH_in = 2.5;

%% ── FIND EXPERIMENT FOLDERS ──────────────────────────────────────────────
% FIX: replaces the hard-coded prefix list; every folder under ROOT_PATH
% whose name carries a tag becomes one experiment.
allDirs = dir(fullfile(ROOT_PATH, '**'));
allDirs = allDirs([allDirs.isdir] & ~ismember({allDirs.name}, {'.', '..'}));

expList = struct('tagIdx', {}, 'folder', {}, 'name', {});
for i = 1:numel(allDirs)
    fname = allDirs(i).name;
    for t = 1:size(TAGS, 1)
        if ~isempty(regexpi(fname, TAGS{t, 2}, 'once')) && ...
           ~(t == 1 && isempty(regexp(fname, TAGS{t, 2}, 'once')))   % cP is case-sensitive
            expList(end+1).tagIdx = t;                               %#ok<SAGROW>
            expList(end).folder   = fullfile(allDirs(i).folder, fname);
            expList(end).name     = fname;
            break;
        end
    end
end

% FIX: drop folders nested inside an already-matched experiment folder
% (e.g. ...\cP_exp\processed_data\cP_plots) so each run is read once.
keep = true(1, numel(expList));
for i = 1:numel(expList)
    for j = 1:numel(expList)
        if i ~= j && startsWith(expList(i).folder, [expList(j).folder filesep])
            keep(i) = false;
        end
    end
end
expList = expList(keep);

if isempty(expList)
    error('No folder containing "cP", "cQhigh" or "cQlow" found under:\n%s', ROOT_PATH);
end

% Sort by importance so the legend reads cP, cQhigh, cQlow
[~, order] = sort([expList.tagIdx]);
expList    = expList(order);

% If a tag appears more than once (replicates), add the folder name to the label
tagCounts = accumarray([expList.tagIdx]', 1, [size(TAGS, 1) 1]);

fprintf('Found %d experiment folder(s):\n', numel(expList));
for i = 1:numel(expList)
    fprintf('   [%s]  %s\n', TAGS{expList(i).tagIdx, 1}, expList(i).folder);
end

%% ── PROCESS EACH EXPERIMENT ──────────────────────────────────────────────
results = struct();

for c = 1:numel(expList)
    tIdx   = expList(c).tagIdx;
    folder = expList(c).folder;

    label = TAGS{tIdx, 3};
    if tagCounts(tIdx) > 1
        label = sprintf('%s (%s)', label, strrep(expList(c).name, '_', '\_'));
    end

    fprintf('\n── Processing: %s ──\n', expList(c).name);

    % ── 1. Sensor offset (FIX: any *offset*.xls(x) inside the folder) ─────
    offFiles = dir(fullfile(folder, '**', '*offset*.xls*'));
    offFiles = offFiles(~startsWith({offFiles.name}, '~$'));   % skip Excel lock files
    if isempty(offFiles)
        error('No *offset*.xlsx file found in:\n%s', folder);
    elseif numel(offFiles) > 1
        fprintf('   ⚠  %d offset files found, using: %s\n', numel(offFiles), offFiles(1).name);
    end
    T_offset = readtable(fullfile(offFiles(1).folder, offFiles(1).name));
    if ~all(ismember({'flowrate', 'pressure_diff'}, T_offset.Properties.VariableNames))
        error('Offset file must have columns "flowrate" and "pressure_diff":\n%s', ...
              fullfile(offFiles(1).folder, offFiles(1).name));
    end
    flowrate_offset      = T_offset.flowrate(1);
    pressure_diff_offset = T_offset.pressure_diff(1);

    % ── 2. Detect experiment type from txt filenames (FIX: any depth) ─────
    files         = dir(fullfile(folder, '**', '*.txt'));
    exp_type      = '';
    pressure_file = '';
    flowrate_file = '';

    for i = 1:numel(files)
        fname = files(i).name;
        fpath = fullfile(files(i).folder, fname);
        if contains(fname, '__ob1_flowrate')
            flowrate_file = fpath;
        elseif contains(fname, '__reader_pressures')
            pressure_file = fpath;
            exp_type      = 'ConstantFlowRate';
        elseif contains(fname, '__ob1_pressures')
            pressure_file = fpath;
        elseif contains(fname, '__reader_flowrate')
            flowrate_file = fpath;
            exp_type      = 'ConstantPressure';
        end
    end

    if isempty(exp_type) || isempty(pressure_file) || isempty(flowrate_file)
        error('Pressure/flowrate txt files not recognized in:\n%s', folder);
    end
    fprintf('   Detected type: %s\n', exp_type);

    % ── 3. Read pressure ─────────────────────────────────────────────────
    p_raw      = readtable(pressure_file, 'Delimiter', '\t', 'ReadVariableNames', false);
    time_str_p = p_raw{:, 1};
    time_sec_p = p_raw{:, 2};

    switch exp_type
        case 'ConstantFlowRate'
            p1 = p_raw{:, 4};
            p2 = p_raw{:, 6};
        case 'ConstantPressure'
            p1 = p_raw{:, 8};
            p2 = p_raw{:, 10};
    end
    deltaP = p1 - p2 - pressure_diff_offset;

    % ── 4. Read flowrate ──────────────────────────────────────────────────
    q_raw      = readtable(flowrate_file, 'Delimiter', '\t', 'ReadVariableNames', false);
    time_str_q = q_raw{:, 1};
    time_sec_q = q_raw{:, 2};

    switch exp_type
        case 'ConstantFlowRate'
            q = q_raw{:, 8};
        case 'ConstantPressure'
            q = q_raw{:, 4};
    end
    q = q - flowrate_offset;

    % ── 5. Find 1-sec logging start ───────────────────────────────────────
    tol = 0.15;

    start_idx_p = find(abs(diff(time_sec_p) - 1) <= tol, 1, 'first');
    if isempty(start_idx_p)
        error('No 1-sec interval found in pressure file: %s', pressure_file);
    end
    start_idx_q = find(abs(diff(time_sec_q) - 1) <= tol, 1, 'first');
    if isempty(start_idx_q)
        error('No 1-sec interval found in flowrate file: %s', flowrate_file);
    end
    % FIX: trim each file at its OWN start index. The old max(p, q) index
    % was applied to both files, which only works if they share row numbers.
    start_idx_p = start_idx_p + 1;
    start_idx_q = start_idx_q + 1;

    % ── 6. Trim ───────────────────────────────────────────────────────────
    time_sec_p = time_sec_p(start_idx_p:end);
    deltaP     = deltaP(start_idx_p:end);
    time_str_p = time_str_p(start_idx_p:end);

    time_sec_q = time_sec_q(start_idx_q:end);
    q          = q(start_idx_q:end);
    time_str_q = time_str_q(start_idx_q:end);

    % ── 7. Correct & build datetime ───────────────────────────────────────
    time_sec_p_corr = [0; cumsum(round(diff(time_sec_p)))];
    time_sec_q_corr = [0; cumsum(round(diff(time_sec_q)))];

    t0_p      = datetime(time_str_p(1), 'InputFormat', 'dd/MM/yyyy_HH:mm:ss');
    t0_q      = datetime(time_str_q(1), 'InputFormat', 'dd/MM/yyyy_HH:mm:ss');
    time_p_dt = t0_p + seconds(time_sec_p_corr);
    time_q_dt = t0_q + seconds(time_sec_q_corr);

    % ── 8. Align on intersecting timestamps ───────────────────────────────
    t0_experiment = min(time_p_dt(1), time_q_dt(1));
    [dt_aligned, idx_p, idx_q] = intersect(time_p_dt, time_q_dt);

    if isempty(dt_aligned)
        error('Pressure and flowrate files share no timestamps in:\n%s', folder);
    end
    gap_sec = seconds(dt_aligned(1) - t0_experiment);
    if gap_sec > 60
        fprintf('   ⚠  First aligned timestamp is %.1f min after experiment start.\n', gap_sec/60);
    end

    % ── 9. Smooth ─────────────────────────────────────────────────────────
    deltaP_smooth = movmean(deltaP(idx_p), SMOOTH_WINDOW);
    q_smooth      = movmean(q(idx_q),      SMOOTH_WINDOW);

    % ── 10–11. Darcy permeability ─────────────────────────────────────────
    q_m3s = q_smooth      * UL_PER_MIN_TO_M3_PER_S;   % m³/s
    dP_Pa = deltaP_smooth * MBAR_TO_PA;               % Pa
    k     = (q_m3s * MU * L) ./ (A * dP_Pa);          % m²

    % FIX: the old guard (1e-3 Pa = 1e-5 mbar) sat far below the sensor's
    % resolution and let near-zero ΔP produce huge, fake k values.
    k(deltaP_smooth < DP_MIN_MBAR) = NaN;
    k(k <= 0)                      = NaN;

    t_hours = hours(dt_aligned - t0_experiment);

    % ── 12. Starting point = highest k at the beginning ───────────────────
    % FIX: the peak is searched only in the first PEAK_SEARCH_H hours (the
    % old code used the global max, which can sit late in the run). k is
    % normalized by THIS value, so each curve starts exactly at 1.
    inWin = t_hours <= t_hours(1) + PEAK_SEARCH_H;
    kWin  = k;
    kWin(~inWin) = NaN;
    % FIX: duplicate max() block removed (it ran the same search twice)
    [k_peak, idx_peak] = max(kWin, [], 'omitnan');
    if isnan(k_peak)
        error('No valid permeability in the first %.1f h for:\n%s', PEAK_SEARCH_H, folder);
    end

    t_peak = t_hours(idx_peak);   % experiment time (h) of the peak

    % FIX: DROP all data before the peak (no more "hold at 1"), then shift
    % time so the peak sits at t = 0 h. Every curve starts at (0, 1).
    t_hours = t_hours(idx_peak:end);
    k       = k(idx_peak:end);
    k_norm  = k / k_peak;

    if ZERO_AT_PEAK
        t_hours = t_hours - t_peak;
    end

    % FIX: end time = last FINITE sample (trailing NaNs do not extend a run)
    lastValid = find(isfinite(k_norm), 1, 'last');

    results(c).label  = label;
    results(c).tagIdx = tIdx;
    results(c).t_hours = t_hours;
    results(c).k       = k;        % raw permeability [m²]
    results(c).k_peak  = k_peak;   % normalization constant [m²]
    results(c).k_norm  = k_norm;   % dimensionless, k / k_peak
    results(c).t_peak  = t_peak;   % experiment time (h) of the peak
    results(c).t_last  = t_hours(lastValid);

    % FIX: t_peak is in experiment time; t_last is in plot time (since peak)
    fprintf('   Peak at t = %.2f h (experiment time)  |  k_peak = %.2e m²  |  run ends at %.2f h (plot time)\n', ...
        t_peak, k_peak, results(c).t_last);
end

%% ── COMMON END TIME = FIRST EXPERIMENT TO END ────────────────────────────
% FIX: every curve is cut at the end time of the shortest experiment.
[t_end, iFirst] = min([results.t_last]);
fprintf('\nPlot ends at t = %.2f h (first experiment to end: %s)\n', ...
    t_end, expList(iFirst).name);

for c = 1:numel(results)
    m = results(c).t_hours <= t_end;
    results(c).t_hours = results(c).t_hours(m);
    results(c).k       = results(c).k(m);
    results(c).k_norm  = results(c).k_norm(m);
end

% FIX: with ZERO_AT_PEAK, every curve starts at its own peak (t = 0 h);
% otherwise the axis opens at the earliest peak in experiment time.
if ZERO_AT_PEAK
    t_start = 0;
else
    t_start = min([results.t_peak]);
end

%% ── LOG OR LINEAR Y-AXIS (on the plotted data) ───────────────────────────
all_k = [];
for c = 1:numel(results)
    all_k = [all_k; results(c).k_norm(isfinite(results(c).k_norm))]; %#ok<AGROW>
end
use_log = log10(max(all_k) / min(all_k)) >= 1;   % log if span ≥ 1 decade
fprintf('k/k_peak spans %.1f decades → %s scale\n', ...
    log10(max(all_k) / min(all_k)), ternary(use_log, 'LOG', 'LINEAR'));

%% ── FIGURE (style of plot_for_manuscripts_1panels.m) ─────────────────────
fig = figure('Color', 'w', ...
    'Units',    'inches', ...
    'Position', [1  1  figW_in  figH_in]);

ax = axes(fig);
hold(ax, 'on');

% FIX: draw the least important curve first so cP sits on top
h = gobjects(numel(results), 1);
for c = numel(results):-1:1
    tIdx = results(c).tagIdx;
    % FIX: clamp sub-floor values so the curve runs along the bottom spine
    % instead of disappearing (log axes drop points outside YLim).
    k_plot = max(results(c).k_norm, Y_FLOOR);
    h(c) = plot(ax, results(c).t_hours, k_plot, TAGS{tIdx, 5}, ...
        'Color',       TAGS{tIdx, 4}, ...
        'LineWidth',   TAGS{tIdx, 6}, ...
        'DisplayName', results(c).label);
end

% Reduction reference line
if ~isempty(REDUCTION_FACTOR)
    reduction_level = 1 / REDUCTION_FACTOR;
    hRef = yline(ax, reduction_level, '--', ...
        'Color',                    [1 0 0], ...
        'LineWidth',                1, ...
        'Alpha',                    1, ...
        'LabelHorizontalAlignment', 'left', ...
        'LabelVerticalAlignment',   'bottom', ...
        'FontSize',                 8, ...
        'FontWeight',               'bold');
    hRef.Annotation.LegendInformation.IconDisplayStyle = 'off';
    y_bounds = [all_k; reduction_level];
else
    y_bounds = all_k;
end

% Y-axis
ax.YScale = 'log';
ylim(ax, [Y_FLOOR  Y_TOP]);

decades       = log10(Y_FLOOR):log10(Y_TOP);            % -4:0
ax.YTick      = 10.^decades;
ax.YTickLabel = arrayfun(@(d) sprintf('10^{%d}', d), decades, 'UniformOutput', false);
ax.YTickLabel{1} = sprintf('<10^{%d}', decades(1));     % "<10^{-4}"
ax.YTickLabel{end} = '1';                               % cleaner than 10^{0}
ax.TickLabelInterpreter = 'tex';
ax.YMinorTick = 'on';

ylabel(ax, 'Normalized permeability (k/k_{peak})', 'FontSize', 9, 'FontWeight', 'bold');

% X-axis (same tick handling as the 1-panel script)
xlim(ax, [t_start  t_end]);
xTicks   = ax.XTick;
ax.XTick = xTicks(xTicks > t_start & xTicks < t_end);
if ZERO_AT_PEAK
    xlabel(ax, 'Experiment time (h)', 'FontSize', 10, 'FontWeight', 'bold');
else
    xlabel(ax, 'Experiment time (h)', 'FontSize', 10, 'FontWeight', 'bold');
end

% Grid + box (same as the 1-panel script)
box(ax, 'on');
grid(ax, 'off');
grid(ax, 'on')
% ax.GridAlpha  = 0.15;
% ax.LineWidth  = 0.8;
% ax.FontSize   = 9;
% ax.FontWeight = 'bold';

ylim(ax,[1e-4 1])

% Legend in importance order (cP, cQhigh, cQlow)
lgd = legend(ax, h, 'Location', 'best', 'Orientation', 'horizontal');
lgd.FontSize   = 12;
lgd.FontWeight = 'bold';
lgd.Box        = 'off';

%% ── EXPORT — PDF vector + TIF 300 dpi ────────────────────────────────────
fig.Units    = 'inches';
fig.Position = [1  1  figW_in  figH_in];

pdfOut = fullfile(ROOT_PATH, 'bulk_permeability_normalized_PNAS.pdf');
tifOut = fullfile(ROOT_PATH, 'bulk_permeability_normalized_PNAS.tif');

exportgraphics(fig, pdfOut, 'ContentType', 'vector');
exportgraphics(fig, tifOut, 'Resolution', 300);

fprintf('Saved:\n  %s\n  %s\n', pdfOut, tifOut);

%% ── HELPER ───────────────────────────────────────────────────────────────
function out = ternary(cond, a, b)
    if cond; out = a; else; out = b; end
end
