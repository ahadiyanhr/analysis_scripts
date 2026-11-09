%% =========================================================================
%  plot_permeability.m
%  Computes and plots smoothed permeability vs. time for three experimental
%  conditions (cP, cQ_low, cQ_high) from raw sensor txt files.
%
%  Darcy's Law:  k = (Q * mu * L) / (A * dP)
%
%  Units:  Q [uL/min] -> [m3/s]
%          dP [mbar]  -> [Pa]
%          k          -> [m2]  (reported as [m2])
%
%  Output: PDF (vector) + TIF (300 dpi) saved next to this script,
%          styled for a high-impact-journal single-column figure.
% =========================================================================
clc; clear; close all;

%% ── CONFIG ───────────────────────────────────────────────────────────────
SMOOTH_WINDOW = 2000;          % movmean window [samples]

% Device geometry
W  = 1e-2;                   % channel width  [m]   (1 cm)
H  = 30e-6;                  % channel height [m]   (30 µm)
L  = 1.5e-2;                 % channel length [m]   (1.5 cm)
A  = W * H;                  % cross-section  [m2]

% Fluid
MU = 8.9e-4;                 % dynamic viscosity of water [Pa·s]

% Unit conversions
UL_PER_MIN_TO_M3_PER_S = 1e-9 / 60;   % µL/min  → m³/s
MBAR_TO_PA              = 100;          % mbar    → Pa

% Conditions to process  {label, prefix}
CONDITIONS = {
    'Constant Pressure',   'cP';
    'Constant Flow (low)', 'cQ_low';
    'Constant Flow (high)','cQ_high';
};

% Paths  (script folder = project root)
scriptDir        = fileparts(mfilename('fullpath'));
sensorReadingPath = pwd; %fullfile(scriptDir, 'raw_data', 'sensor_readings');
logsPath          = pwd; %fullfile(scriptDir, 'logs');

%% ── PROCESS EACH CONDITION ───────────────────────────────────────────────
results = struct();

for c = 1:size(CONDITIONS, 1)
    label  = CONDITIONS{c, 1};
    prefix = CONDITIONS{c, 2};

    fprintf('\n── Processing: %s (%s) ──\n', label, prefix);

    % ── 1. Sensor offset ─────────────────────────────────────────────────
    offsetFile = fullfile(logsPath, sprintf('%s__sensor_offset.xlsx', prefix));
    T_offset   = readtable(offsetFile);
    flowrate_offset    = T_offset.flowrate(1);
    pressure_diff_offset = T_offset.pressure_diff(1);

    % ── 2. Detect experiment type from filenames ──────────────────────────
    files = dir(fullfile(sensorReadingPath, sprintf('%s__*.txt', prefix)));
    exp_type      = '';
    pressure_file = '';
    flowrate_file = '';

    for i = 1:length(files)
        fname = files(i).name;
        if contains(fname, '__ob1_flowrate')
            flowrate_file = fname;
        elseif contains(fname, '__reader_pressures')
            pressure_file = fname;
            exp_type      = 'ConstantFlowRate';
        elseif contains(fname, '__ob1_pressures')
            pressure_file = fname;
        elseif contains(fname, '__reader_flowrate')
            flowrate_file = fname;
            exp_type      = 'ConstantPressure';
        end
    end

    if isempty(exp_type)
        error('Experiment type not recognized for prefix: %s', prefix);
    end
    fprintf('   Detected type: %s\n', exp_type);

    % ── 3. Read pressure ─────────────────────────────────────────────────
    p_raw      = readtable(fullfile(sensorReadingPath, pressure_file), ...
                           'Delimiter', '\t', 'ReadVariableNames', false);
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
    q_raw      = readtable(fullfile(sensorReadingPath, flowrate_file), ...
                           'Delimiter', '\t', 'ReadVariableNames', false);
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

    dt_p        = diff(time_sec_p);
    start_idx_p = find(abs(dt_p - 1) <= tol, 1, 'first');
    if isempty(start_idx_p)
        error('No 1-sec interval found in pressure file: %s', pressure_file);
    end
    start_idx_p = start_idx_p + 1;

    dt_q        = diff(time_sec_q);
    start_idx_q = find(abs(dt_q - 1) <= tol, 1, 'first');
    if isempty(start_idx_q)
        error('No 1-sec interval found in flowrate file: %s', flowrate_file);
    end
    start_idx_q = start_idx_q + 1;

    start_idx = max(start_idx_p, start_idx_q);

    % ── 6. Trim ───────────────────────────────────────────────────────────
    time_sec_p = time_sec_p(start_idx:end);
    p1         = p1(start_idx:end);
    p2         = p2(start_idx:end);
    deltaP     = deltaP(start_idx:end);
    time_str_p = time_str_p(start_idx:end);

    time_sec_q = time_sec_q(start_idx:end);
    q          = q(start_idx:end);
    time_str_q = time_str_q(start_idx:end);

    % ── 7. Correct & build datetime ───────────────────────────────────────
    time_sec_p_corr = [0; cumsum(round(diff(time_sec_p)))];
    time_sec_q_corr = [0; cumsum(round(diff(time_sec_q)))];

    t0_p       = datetime(time_str_p(1), 'InputFormat', 'dd/MM/yyyy_HH:mm:ss');
    t0_q       = datetime(time_str_q(1), 'InputFormat', 'dd/MM/yyyy_HH:mm:ss');
    time_p_dt  = t0_p + seconds(time_sec_p_corr);
    time_q_dt  = t0_q + seconds(time_sec_q_corr);

    % ── 8. Align on intersecting timestamps ───────────────────────────────
    % Anchor t=0 to the earliest clock time across both sensors BEFORE
    % intersect(), so the time axis always starts at 0 regardless of which
    % file began logging first.
    t0_experiment = min(time_p_dt(1), time_q_dt(1));

    [dt_aligned, idx_p, idx_q] = intersect(time_p_dt, time_q_dt);

    % Diagnostic: warn if first aligned point is far from file starts
    gap_sec = seconds(dt_aligned(1) - t0_experiment);
    if gap_sec > 60
        fprintf('   ⚠  First aligned timestamp is %.1f min after experiment start.\n', gap_sec/60);
        fprintf('      Likely cause: one sensor file has a gap at its beginning.\n');
        fprintf('      Time axis will still start at 0 (anchored to earliest file start).\n');
    end

    deltaP_aligned = deltaP(idx_p);
    q_aligned      = q(idx_q);

    % ── 9. Smooth ─────────────────────────────────────────────────────────
    deltaP_smooth = movmean(deltaP_aligned, SMOOTH_WINDOW);
    q_smooth      = movmean(q_aligned,      SMOOTH_WINDOW);

    % ── 10. Convert units ─────────────────────────────────────────────────
    q_m3s  = q_smooth      * UL_PER_MIN_TO_M3_PER_S;   % m³/s
    dP_Pa  = deltaP_smooth * MBAR_TO_PA;                % Pa

    % ── 11. Darcy permeability ────────────────────────────────────────────
    % k = Q * mu * L / (A * dP)
    k = (q_m3s * MU * L) ./ (A * dP_Pa);               % m²

    % Guard against division by near-zero pressure
    k(abs(dP_Pa) < 1e-3) = NaN;
    k(k <= 0)             = NaN;

    % ── 12. Time axis: hours from experiment start ─────────────────────────
    % Subtract the earliest file-start time (not first intersect point)
    % so the x-axis always opens at 0, even if there is a gap before
    % the two sensors first share a common timestamp.
    t_hours = hours(dt_aligned - t0_experiment);

    % Store results
    results(c).label   = label;
    results(c).prefix  = prefix;
    results(c).t_hours = t_hours;
    results(c).k       = k;

    fprintf('   Duration: %.2f h  |  k range: %.2e – %.2e m²\n', ...
        t_hours(end), min(k, [], 'omitnan'), max(k, [], 'omitnan'));
end

%% ── CHECK IF LOG SCALE IS WARRANTED ─────────────────────────────────────
all_k = [];
for c = 1:numel(results)
    all_k = [all_k; results(c).k(isfinite(results(c).k))]; %#ok<AGROW>
end
k_range_decades = log10(max(all_k) / min(all_k));
use_log = k_range_decades >= 1;   % log scale if span ≥ 1 order of magnitude
fprintf('\nk spans %.1f decades → %s scale\n', k_range_decades, ...
    ternary(use_log, 'LOG', 'LINEAR'));

t_end = max(arrayfun(@(r) r.t_hours(end), results));

%% ── FIGURE: HIGH-IMPACT-JOURNAL SINGLE-COLUMN STYLE ─────────────────────
% Design choices:
%   • Okabe–Ito colorblind-safe palette, paired with distinct line styles
%     so curves stay distinguishable in grayscale print.
%   • tiledlayout('compact') instead of hand-tuned normalized Position
%     values, so margins stay correct if labels/fonts change.
%   • Log-decade y-limits (when warranted) with a labeled minor grid,
%     instead of MATLAB's default tight/arbitrary bounds.
%   • Legend placed by named location with a light border, not hard-coded
%     pixel coordinates that break if the figure is resized.
FONT      = 'Helvetica';
FONT_SIZE = 8;

COLORS = [
    0.000  0.447  0.698;   % blue          → Constant Pressure
    0.902  0.624  0.000;   % orange        → Constant Flow (low)
    0.000  0.620  0.451;   % bluish-green  → Constant Flow (high)
];
LINESTYLES = {'-', '--', '-.'};
LINEWIDTH  = 1.3;

% PNAS single column: 8.7 cm wide; slightly taller than golden-ratio to
% leave headroom for the legend without overlapping the curves.
fig_w_cm = 8.7;
fig_h_cm = 6.7;

fig = figure('Units', 'centimeters', ...
             'Position', [2 2 fig_w_cm fig_h_cm], ...
             'Color', 'white');

tl = tiledlayout(fig, 1, 1, 'Padding', 'compact', 'TileSpacing', 'compact');
ax = nexttile(tl);
hold(ax, 'on');

% ── Plot each condition ───────────────────────────────────────────────────
h = gobjects(numel(results), 1);
for c = 1:numel(results)
    h(c) = plot(ax, results(c).t_hours, results(c).k, LINESTYLES{c}, ...
        'DisplayName', results(c).label, ...
        'Color',       COLORS(c, :), ...
        'LineWidth',   LINEWIDTH);
end

% ── Y-axis scale & limits ─────────────────────────────────────────────────
if use_log
    ax.YScale = 'log';
    % Round out to the nearest decade for a clean, evenly-spaced log grid.
    ylo = 10^floor(log10(min(all_k)));
    yhi = 10^ceil(log10(max(all_k)));
    ax.YLim      = [ylo yhi];
    ax.YMinorGrid = 'on';
    ax.YMinorTick = 'on';
else
    ax.YScale = 'linear';
    pad = 0.08 * (max(all_k) - min(all_k));
    ax.YLim      = [min(all_k) - pad, max(all_k) + pad];
    ax.YMinorGrid = 'off';
end

% ── Axes properties ────────────────────────────────────────────────────────
set(ax, ...
    'FontName',           FONT, ...
    'FontSize',           FONT_SIZE, ...
    'Box',                'on', ...
    'LineWidth',          0.75, ...
    'TickDir',            'out', ...
    'TickLength',         [0.012 0.012], ...
    'XColor',             [0.15 0.15 0.15], ...
    'YColor',             [0.15 0.15 0.15], ...
    'XMinorTick',         'on', ...
    'XGrid',              'off', ...
    'YGrid',              'on', ...
    'GridLineStyle',      ':', ...
    'GridColor',          [0.5 0.5 0.5], ...
    'GridAlpha',          0.35, ...
    'MinorGridLineStyle', ':', ...
    'MinorGridColor',     [0.5 0.5 0.5], ...
    'MinorGridAlpha',     0.12, ...
    'Layer',              'top');

xlim(ax, [0, t_end]);

xlabel(ax, 'Time (h)', ...
    'FontName', FONT, 'FontSize', FONT_SIZE + 1, 'FontWeight', 'bold');
ylabel(ax, 'Permeability, k (m^{2})', ...
    'FontName', FONT, 'FontSize', FONT_SIZE + 1, 'FontWeight', 'bold');

% ── Legend ───────────────────────────────────────────────────────────────
lgd = legend(ax, h, 'Location', 'northeast');
set(lgd, ...
    'FontName',  FONT, ...
    'FontSize',  FONT_SIZE - 1, ...
    'Box',       'on', ...
    'EdgeColor', [0.7 0.7 0.7], ...
    'Color',     'white');

%% ── SAVE ─────────────────────────────────────────────────────────────────
pdfOut = fullfile(scriptDir, 'permeability_vs_time.pdf');
tifOut = fullfile(scriptDir, 'permeability_vs_time.tif');

exportgraphics(fig, pdfOut, 'ContentType', 'vector', 'BackgroundColor', 'white');
exportgraphics(fig, tifOut, 'Resolution', 300, 'BackgroundColor', 'white');

fprintf('\n✅ Figure saved:\n   %s\n   %s\n', pdfOut, tifOut);

%% ── HELPER ───────────────────────────────────────────────────────────────
function out = ternary(cond, a, b)
    if cond; out = a; else; out = b; end
end