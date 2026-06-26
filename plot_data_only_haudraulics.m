%% Single-panel hydraulics figure
%
% PANEL: flowrate Q (left y) + pressure gradient ΔP (right y)
%
% Reads raw sensor txt files directly — no pre-cleaned CSVs needed.
% Experiment type (cQ or cP) is auto-detected from filenames.
% Output: 7 × 2.5 inch PDF + TIF matching the two-panel figure style.

clear; clc; close all;

%% -------------------------------------------------
% Settings
%% -------------------------------------------------
window = 20;   % moving-average smoothing window (samples) applied to both Q and ΔP

% ---- ΔP spike / outlier removal ----
% Set remove_dp_outliers = true to clip large fluctuations before smoothing.
% Samples whose absolute deviation from the local median exceeds
% dp_outlier_threshold * MAD (median absolute deviation) are replaced by
% the local median. Increase dp_outlier_threshold to allow more variation;
% decrease it to be more aggressive. dp_mad_window controls the local
% neighbourhood used to compute median and MAD (in samples).
remove_dp_outliers  = true;      % true = on, false = off
dp_outlier_threshold = 3;        % number of MADs beyond which a sample is an outlier
dp_mad_window        = 60;       % local window for median and MAD (samples)

%% -------------------------------------------------
% Paths
%% -------------------------------------------------
mainPath    = pwd;
cd(mainPath); cd('../');
projectPath = pwd;

cd(projectPath); cd('raw_data\sensor_readings\');
sensorReadingPath = pwd;

cd(projectPath); cd('logs\');
logsPath = pwd;

cd(projectPath); cd('processed_data\plots\');
plotPath = pwd;

%% -------------------------------------------------
% Auto-detect experiment type and file names
%% -------------------------------------------------
files = dir(fullfile(sensorReadingPath, '*.txt'));

for i = 1:length(files)
    fname = files(i).name;
    if contains(fname, '__ob1_flowrate')
        flowrate_file = fname;
    elseif contains(fname, '__reader_pressures')
        pressure_file = fname;
        exp_type = 'ConstantFlowRate';
    elseif contains(fname, '__ob1_pressures')
        pressure_file = fname;
    elseif contains(fname, '__reader_flowrate')
        flowrate_file = fname;
        exp_type = 'ConstantPressure';
    end
end

if ~exist('exp_type', 'var')
    error('Experiment type not recognized. Check that files follow the expected naming convention.');
end
fprintf('Detected experiment type: %s\n', exp_type);

%% -------------------------------------------------
% Sensor offsets
%% -------------------------------------------------
calibFile = dir(fullfile(logsPath, 'sensor_offset.xlsx'));
T = readtable(fullfile(logsPath, calibFile.name));
flowrate_offset      = T.flowrate(1);
pressure_diff_offset = T.pressure_diff(1);

%% -------------------------------------------------
% Read pressure data
%% -------------------------------------------------
p_raw      = readtable(fullfile(sensorReadingPath, pressure_file), ...
                 'Delimiter', '\t', 'ReadVariableNames', false);
time_str_p = p_raw{:,1};
time_sec_p = p_raw{:,2};

switch exp_type
    case 'ConstantFlowRate'
        p1 = p_raw{:,4};
        p2 = p_raw{:,6};
    case 'ConstantPressure'
        p1 = p_raw{:,8};
        p2 = p_raw{:,10};
end
deltaP = p1 - p2 - pressure_diff_offset;

%% -------------------------------------------------
% Read flowrate data
%% -------------------------------------------------
q_raw      = readtable(fullfile(sensorReadingPath, flowrate_file), ...
                 'Delimiter', '\t', 'ReadVariableNames', false);
time_str_q = q_raw{:,1};
time_sec_q = q_raw{:,2};

switch exp_type
    case 'ConstantFlowRate'
        q = q_raw{:,8};
    case 'ConstantPressure'
        q = q_raw{:,4};
end
q = q - flowrate_offset;

%% -------------------------------------------------
% Find first index where dt ≈ 1 s (proper logging start)
%% -------------------------------------------------
tol = 0.15;

dt_p        = diff(time_sec_p);
start_idx_p = find(abs(dt_p - 1) <= tol, 1, 'first');
if isempty(start_idx_p)
    error('No 1 s interval found in pressure file.');
end
start_idx_p = start_idx_p + 1;

dt_q        = diff(time_sec_q);
start_idx_q = find(abs(dt_q - 1) <= tol, 1, 'first');
if isempty(start_idx_q)
    error('No 1 s interval found in flowrate file.');
end
start_idx_q = start_idx_q + 1;

start_idx = max(start_idx_p, start_idx_q);

%% -------------------------------------------------
% Trim to proper start
%% -------------------------------------------------
time_sec_p = time_sec_p(start_idx:end);
deltaP     = deltaP(start_idx:end);
time_str_p = time_str_p(start_idx:end);

time_sec_q = time_sec_q(start_idx:end);
q          = q(start_idx:end);
time_str_q = time_str_q(start_idx:end);

%% -------------------------------------------------
% Normalize time increments
%% -------------------------------------------------
time_sec_p_corrected = [0; cumsum(round(diff(time_sec_p)))];
time_sec_q_corrected = [0; cumsum(round(diff(time_sec_q)))];

start_time_p     = datetime(time_str_p(1), 'InputFormat', 'dd/MM/yyyy_HH:mm:ss');
time_p_corrected = start_time_p + seconds(time_sec_p_corrected);

start_time_q     = datetime(time_str_q(1), 'InputFormat', 'dd/MM/yyyy_HH:mm:ss');
time_q_corrected = start_time_q + seconds(time_sec_q_corrected);

%% -------------------------------------------------
% Align on exact matching timestamps
%% -------------------------------------------------
[dt_aligned, idx_p, idx_q] = intersect(time_p_corrected, time_q_corrected);

deltaP_aligned = deltaP(idx_p);
q_aligned      = q(idx_q);

%% -------------------------------------------------
% ΔP outlier removal (on/off via remove_dp_outliers)
%% -------------------------------------------------
if remove_dp_outliers
    % Compute local median and MAD in a sliding window
    dp_local_med = movmedian(deltaP_aligned, dp_mad_window);
    dp_local_mad = movmedian(abs(deltaP_aligned - dp_local_med), dp_mad_window);
    dp_local_mad(dp_local_mad == 0) = eps;   % avoid division by zero

    % Flag outliers
    dp_zscore  = abs(deltaP_aligned - dp_local_med) ./ dp_local_mad;
    is_outlier = dp_zscore > dp_outlier_threshold;

    % Replace outliers with local median
    deltaP_clean = deltaP_aligned;
    deltaP_clean(is_outlier) = dp_local_med(is_outlier);

    fprintf('ΔP outlier removal: %d / %d samples replaced (%.1f%%)\n', ...
        sum(is_outlier), numel(is_outlier), 100*mean(is_outlier));
else
    deltaP_clean = deltaP_aligned;
    fprintf('ΔP outlier removal: OFF\n');
end

%% -------------------------------------------------
% Smooth
%% -------------------------------------------------
dp_smooth = movmean(deltaP_clean, window);
q_smooth  = movmean(q_aligned,    window);

%% -------------------------------------------------
% Common t0 and hours axis
%% -------------------------------------------------
t0      = dt_aligned(1);
hours_t = hours(dt_aligned - t0);

%% -------------------------------------------------
% USER-DEFINED EVENT LINES
% Edit eventTimes (elapsed hours from t0) and eventLabels as needed.
% Set to empty arrays to disable: eventTimes = []; eventLabels = {};
%% -------------------------------------------------
eventTimes  = [71.87];          % <-- edit: e.g. [24, 48, 72]
eventLabels = {'move the reactor'};          % <-- edit: e.g. {'PSS onset', 'Sloughing', 'Re-clogging'}
eventColor  = [0.0 0.0 0.0];
eventLW     = 1;

%% -------------------------------------------------
% Colors (same as two-panel figure)
%% -------------------------------------------------
clrQ  = [0.129  0.400  0.675];   % steel blue — flowrate
clrDP = [0.698  0.094  0.169];   % crimson    — pressure

lineWMain = 1.5;
axisfontsize = 9;

%% -------------------------------------------------
% Figure: 7 × 2.5 inch, white background
%% -------------------------------------------------
figW_in = 7;
figH_in = 2.5;
fig = figure('Color', 'w', ...
    'Units',    'inches', ...
    'Position', [1 1 figW_in figH_in]);

ax = axes(fig);
hold(ax, 'on');

% ---- Left y-axis: flowrate ----
yyaxis(ax, 'left');
plot(ax, hours_t, q_smooth, '-', ...
    'Color',     clrQ, ...
    'LineWidth', lineWMain);

ylabel(ax, 'Flowrate (\muL min^{-1})', ...
    'Color', clrQ, 'FontSize', axisfontsize, 'FontWeight', 'bold');
ax.YColor = clrQ;
ylim(ax, [-0.5  12.5]);
ax.YTick      = 0:2:12;
ax.YTickLabel = arrayfun(@num2str, 0:2:12, 'UniformOutput', false);

% Zero-flowrate reference line
hZeroQ = yline(ax, 0, '--', 'Color', clrQ, 'LineWidth', 0.9, 'Alpha', 0.5);
hZeroQ.Annotation.LegendInformation.IconDisplayStyle = 'off';

% ---- Right y-axis: pressure ----
yyaxis(ax, 'right');
plot(ax, hours_t, dp_smooth, '-', ...
    'Color',     clrDP, ...
    'LineWidth', lineWMain);

ylabel(ax, '\DeltaP (mbar)', ...
    'Color', clrDP, 'FontSize', axisfontsize, 'FontWeight', 'bold');
ax.YColor = clrDP;
ylim(ax, [0  max(dp_smooth) * 1.15 + eps]);

xlabel(ax, 'Experiment time (h)', 'FontSize', axisfontsize, 'FontWeight', 'bold');

% ---- Formatting ----
grid(ax, 'on');
box(ax, 'on');
ax.GridAlpha  = 0.15;
ax.LineWidth  = 0.8;
ax.FontWeight = 'bold';
xlim(ax, [0  hours_t(end)]);

%% -------------------------------------------------
% Event lines (if defined)
%% -------------------------------------------------
for ev = 1:length(eventTimes)
    et = eventTimes(ev);
    hev = xline(ax, et, '--', ...
        'Color', eventColor, 'LineWidth', eventLW, 'Alpha', 0.75);
    hev.Annotation.LegendInformation.IconDisplayStyle = 'off';
end

% Event labels above the panel (overlay axes, same approach as two-panel script)
if ~isempty(eventLabels)
    drawnow;
    axEvt = axes('Units',            'normalized', ...
                 'Position',         ax.Position, ...
                 'Color',            'none', ...
                 'XLim',             ax.XLim, ...
                 'YLim',             [0 1], ...
                 'XColor',           'none', ...
                 'YColor',           'none', ...
                 'Box',              'off', ...
                 'HitTest',          'off', ...
                 'HandleVisibility', 'off');

    for ev = 1:length(eventTimes)
        xNorm = (eventTimes(ev) - axEvt.XLim(1)) / diff(axEvt.XLim);
        text(axEvt, xNorm, 1.03, eventLabels{ev}, ...
            'Units',               'normalized', ...
            'Color',               eventColor, ...
            'FontSize',            9, ...
            'FontWeight',          'bold', ...
            'HorizontalAlignment', 'center', ...
            'VerticalAlignment',   'bottom', ...
            'Rotation',            0, ...
            'Interpreter',         'none', ...
            'Clipping',            'off');
    end

    lEvtPos = addlistener(ax, 'Position', 'PostSet', ...
        @(~,~) set(axEvt, 'Position', ax.Position, 'XLim', ax.XLim));
    lEvtLim = addlistener(ax, 'XLim', 'PostSet', ...
        @(~,~) set(axEvt, 'XLim', ax.XLim));
    setappdata(fig, 'ListenerEvtPos', lEvtPos);
    setappdata(fig, 'ListenerEvtLim', lEvtLim);
end

%% -------------------------------------------------
% Save
%% -------------------------------------------------
pdfOut = fullfile(plotPath, 'hydraulics_only.pdf');
tifOut = fullfile(plotPath, 'hydraulics_only.tif');

exportgraphics(fig, pdfOut, 'ContentType', 'vector');
exportgraphics(fig, tifOut, 'Resolution', 300);

fprintf('Saved:\n  %s\n  %s\n', pdfOut, tifOut);