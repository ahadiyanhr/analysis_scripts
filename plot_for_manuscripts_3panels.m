%% Three-panel combined plot
% TOP:
%   - Growth [% of pore area]
%   - Erosion [% of pore area]
%   - Net [% of pore area]
%
% MIDDLE:
%   - Normalized biomass occupation
%   - Bulk DO
%
% BOTTOM:
%   - Flowrate
%   - Pressure
%
% X-axis:
%   - experiment time in hours, where earliest datetime across
%     flowrate, pressure, and imaging timestamps = 0
%
% Top x-axis:
%   - image numbers (#00, #01, #02, ...)

clear; clc; close all;

%% -------------------------------------------------
% Setup
%% -------------------------------------------------

% Scripts path
mainPath = pwd;

% Project path
cd(mainPath);
cd('../');
projectPath = pwd;

% Clean data path
cd(projectPath);
cd('processed_data\pq_cleaned_data\');
pdCleanedPath = pwd;

% Logs path
cd(projectPath);
cd('logs\');
logsPath = pwd;

% Biomass and BulkDO path
cd(projectPath);
cd('processed_data\biomass_occupation_bulkDO\');
bioDOPath = pwd;

% Growth/Erosion metrics path
cd(projectPath);
cd('processed_data\growth_erosion_timepoints\');
growthMetricsPath = pwd;

% Plots path
cd(projectPath);
cd('processed_data\plots\');
plotPath = pwd;

%% -------------------------------------------------
% File names
%% -------------------------------------------------
flowrateFile   = 'cleaned_flowrate.csv';
pressFile      = 'cleaned_pressures.csv';
timeFile       = 'imaging_timestamp.xlsx';
metricsMatFile = 'growth_erosion.mat';

listing = dir(fullfile(bioDOPath, 'sensitivity_*_main_results.mat'));

if isempty(listing)
    error('No matching sensitivity MAT file found in:\n%s', bioDOPath);
end

bioMatFile = listing(1).name;   % take the first match

%% -------------------------------------------------
% Read flowrate data
%% -------------------------------------------------
TTq = readtable(fullfile(pdCleanedPath, flowrateFile), 'TextType', 'string');
TTq.datetime = datetime(TTq.datetime, ...
    'InputFormat', 'MM/dd/yyyy hh:mm:ss a');

t_q = TTq.datetime(:);
q_smooth = TTq.q_smooth(:);

%% -------------------------------------------------
% Read pressure data
%% -------------------------------------------------
TTp = readtable(fullfile(pdCleanedPath, pressFile), 'TextType', 'string');
TTp.datetime = datetime(TTp.datetime, ...
    'InputFormat', 'MM/dd/yyyy hh:mm:ss a');

t_p = TTp.datetime(:);
dp_smooth = TTp.dP_smooth(:);

%% -------------------------------------------------
% Read imaging timestamps
%% -------------------------------------------------
imagingTime = readtable(fullfile(logsPath, timeFile), 'TextType', 'string');
t_img = datetime(imagingTime.Datetime, 'InputFormat', 'yyyy-MM-dd HH:mm:ss');
t_img = t_img(:);

%% -------------------------------------------------
% Read biomass occupation and bulk DO
%% -------------------------------------------------
S = load(fullfile(bioDOPath, bioMatFile));

biomass_occ = S.data.biomass_occupation(:);
bulk_DO     = S.data.bulk_do(:);

if length(biomass_occ) ~= length(t_img)
    error('Length of biomass occupation does not match imaging timestamps.');
end

if length(bulk_DO) ~= length(t_img)
    error('Length of bulk DO does not match imaging timestamps.');
end

%% -------------------------------------------------
% Read growth / erosion / net metrics
%% -------------------------------------------------
M = load(fullfile(growthMetricsPath, metricsMatFile));

% Handle both possible save styles
if isfield(M, 'resultStruct')
    growth_pct  = M.resultStruct.growth_pct(:);
    erosion_pct = M.resultStruct.erosion_pct(:);
    net_pct     = M.resultStruct.net_pct(:);
else
    growth_pct  = M.growthPct(:);
    erosion_pct = M.erosionPct(:);
    net_pct     = M.netPct(:);
end

%% -------------------------------------------------
% Define experiment time zero
% IMPORTANT:
% Use the same t0 for ALL panels so they align correctly
%% -------------------------------------------------
t0 = min([t_q; t_p; t_img]);

hours_q   = hours(t_q   - t0);
hours_p   = hours(t_p   - t0);
hours_img = hours(t_img - t0);

% Growth/erosion/net correspond to intervals between THRESHOLDED images.
% Thresholded images start at image #2 (0-based) = t_img(3) in MATLAB.
% Each interval is tagged to its end frame:
%   interval 1: t_img(3) → t_img(4)  → tagged to t_img(4)
%   interval 2: t_img(4) → t_img(5)  → tagged to t_img(5)  ...
% So the correct time axis for metrics is hours_img(4:end).
threshOffset   = 1;                              % # of leading images skipped
hours_interval = hours_img((threshOffset+2):end);

if length(growth_pct) ~= length(hours_interval)
    error('Length of growth_pct does not match image intervals.');
end
if length(erosion_pct) ~= length(hours_interval)
    error('Length of erosion_pct does not match image intervals.');
end
if length(net_pct) ~= length(hours_interval)
    error('Length of net_pct does not match image intervals.');
end

%% -------------------------------------------------
% OPTIONAL: crop to first X hours
% Uncomment if needed
%% -------------------------------------------------
% maxHour = 100;
%
% mask_q   = hours_q <= maxHour;
% mask_p   = hours_p <= maxHour;
% mask_img = hours_img <= maxHour;
% mask_int = hours_interval <= maxHour;
%
% hours_q_plot   = hours_q(mask_q);
% q_smooth_plot  = q_smooth(mask_q);
%
% hours_p_plot   = hours_p(mask_p);
% dp_smooth_plot = dp_smooth(mask_p);
%
% hours_img_plot   = hours_img(mask_img);
% biomass_occ_plot = biomass_occ(mask_img);
% bulk_DO_plot     = bulk_DO(mask_img);
%
% hours_int_plot   = hours_interval(mask_int);
% growth_plot      = growth_pct(mask_int);
% erosion_plot     = erosion_pct(mask_int);
% net_plot         = net_pct(mask_int);

%% -------------------------------------------------
% Use full range by default
%% -------------------------------------------------
hours_q_plot   = hours_q;
q_smooth_plot  = q_smooth;

hours_p_plot   = hours_p;
dp_smooth_plot = dp_smooth;

hours_img_plot   = hours_img;
biomass_occ_plot = biomass_occ;
bulk_DO_plot     = bulk_DO;

hours_int_plot = hours_interval;
growth_plot    = growth_pct;
erosion_plot   = erosion_pct;
net_plot       = net_pct;

%% -------------------------------------------------
% Image labels
%% -------------------------------------------------
step = 10;
idx = 1:step:length(hours_img_plot);
imgLabels = arrayfun(@(k) sprintf('#%02d', k-1), idx, 'UniformOutput', false);

%% -------------------------------------------------
% Plot
%% -------------------------------------------------
figure('Color','w','Position',[100 80 1250 950]);

tl = tiledlayout(3,1,'TileSpacing','loose','Padding','compact');

%% =================================================
% TOP PLOT: Growth / Erosion / Net
%% =================================================
axTop = nexttile(tl,1);
hold(axTop, 'on');

% --- Filled area: Growth (positive, green) ---
fill(axTop, ...
    [hours_int_plot(:); flipud(hours_int_plot(:))], ...
    [growth_plot(:);    zeros(size(growth_plot(:)))], ...
    [0 0.60 0], ...
    'FaceAlpha', 0.25, ...
    'EdgeColor', 'none');

hGrowth = plot(axTop, hours_int_plot, growth_plot, '-', ...
    'Color', [0 0.60 0], ...
    'LineWidth', 1.2);

% --- Filled area: Erosion (drawn as negative, red) ---
erosion_neg = -abs(erosion_plot);          % force below zero

fill(axTop, ...
    [hours_int_plot(:);   flipud(hours_int_plot(:))], ...
    [erosion_neg(:);      zeros(size(erosion_neg(:)))], ...
    [0.85 0.20 0.20], ...
    'FaceAlpha', 0.25, ...
    'EdgeColor', 'none');

hErosion = plot(axTop, hours_int_plot, erosion_neg, '-', ...
    'Color', [0.85 0.20 0.20], ...
    'LineWidth', 1.2);

% --- Net: black line, no markers ---
hNet = plot(axTop, hours_int_plot, net_plot, '-', ...
    'Color', [0.10 0.10 0.10], ...
    'LineWidth', 1.5);

% --- Zero reference line ---
hZero = yline(axTop, 0, '-k', 'LineWidth', 0.75);
hZero.Annotation.LegendInformation.IconDisplayStyle = 'off';

% --- Symmetric y-axis centred on zero ---
yAbsMax = max([ abs(growth_plot(:)); abs(erosion_neg(:)); abs(net_plot(:)) ]);
yPad    = yAbsMax * 0.15;                  % 15 % padding
ylim(axTop, [-(yAbsMax + yPad), (yAbsMax + yPad)]);

ylabel(axTop, {'Net Biomass Intensity Change', '[% of pore area]'}, ...
    'FontSize', 12, 'FontWeight', 'bold');

grid(axTop, 'on');
box(axTop,  'on');
axTop.XTickLabel = [];
axTop.XTick      = [];

lgdTop = legend(axTop, [hGrowth, hErosion, hNet], ...
    {'Growth', 'Erosion (negative axis)', 'Net'}, ...
    'Location', 'best', ...
    'FontSize', 10);
lgdTop.AutoUpdate = 'off';

%% =================================================
% MIDDLE PLOT: Biomass occupation + Bulk DO
%% =================================================
axMid = nexttile(tl,2);

yyaxis(axMid, 'left')

bio_norm_plot = biomass_occ_plot;

plot(axMid, hours_img_plot, bio_norm_plot, '-o', ...
    'Color', [1 0.5 0], ...
    'MarkerFaceColor', [1 0.5 0], ...
    'MarkerSize', 4, ...
    'LineWidth', 0.5);

ylabel(axMid, {'Pore Space Occupied by Biomass', '(% of pore area)'}, ...
    'Color', [1 0.5 0], 'FontSize', 12, 'FontWeight', 'bold');
axMid.YColor = [1 0.5 0];

yyaxis(axMid, 'right')

plot(axMid, hours_img_plot, bulk_DO_plot, '-o', ...
    'Color', [0 0.45 0.74], ...
    'MarkerFaceColor', [0 0.45 0.74], ...
    'MarkerSize', 4, ...
    'LineWidth', 0.5);

ylabel(axMid, 'Bulk DO [mg/L]', ...
    'Color', [0 0.45 0.74], 'FontSize', 12, 'FontWeight', 'bold');
axMid.YColor = [0 0.45 0.74];

grid(axMid, 'on');
box(axMid, 'on');
axMid.XTickLabel = [];
axMid.XTick = [];

%% =================================================
% BOTTOM PLOT: Flowrate + Pressure
%% =================================================
axBot = nexttile(tl,3);

yyaxis(axBot, 'left')

plot(axBot, hours_q_plot, q_smooth_plot, ...
    'Color', [0 0.35 0], ...
    'LineWidth', 2);

ylabel(axBot, 'Flowrate [\muL/min]', ...
    'Color', [0 0.35 0], 'FontSize', 12, 'FontWeight', 'bold');
axBot.YColor = [0 0.35 0];

yyaxis(axBot, 'right')

plot(axBot, hours_p_plot, dp_smooth_plot, ...
    'Color', [1 0 0], ...
    'LineWidth', 0.5);

ylabel(axBot, 'Pressure [mbar]', ...
    'Color', [1 0 0], 'FontSize', 12, 'FontWeight', 'bold');
axBot.YColor = [1 0 0];

xlabel(axBot, 'Experiment time (hours)', ...
    'FontSize', 12, 'FontWeight', 'bold');

grid(axBot, 'on');
box(axBot, 'on');

%% -------------------------------------------------
% Link x axes and define x range
%% -------------------------------------------------
linkaxes([axTop axMid axBot], 'x');

xMin = 0;
xMax = max([hours_q_plot(:); hours_p_plot(:); hours_img_plot(:); hours_int_plot(:)]);

xlim(axTop, [xMin xMax]);
xlim(axMid, [xMin xMax]);
xlim(axBot, [xMin xMax]);

%% -------------------------------------------------
% Add vertical lines at imaging times
%% -------------------------------------------------
for i = idx
    hx1 = xline(axTop, hours_img_plot(i), ':', ...
        'Color', [0.6 0.6 0.6], 'LineWidth', 2);
    hx1.Annotation.LegendInformation.IconDisplayStyle = 'off';

    hx2 = xline(axMid, hours_img_plot(i), ':', ...
        'Color', [0.6 0.6 0.6], 'LineWidth', 2);
    hx2.Annotation.LegendInformation.IconDisplayStyle = 'off';

    hx3 = xline(axBot, hours_img_plot(i), ':', ...
        'Color', [0.6 0.6 0.6], 'LineWidth', 2);
    hx3.Annotation.LegendInformation.IconDisplayStyle = 'off';
end

%% -------------------------------------------------
% Create top x-axis for image numbers
%% -------------------------------------------------
axTopX = axes('Units','normalized', ...
    'Position', axTop.Position, ...
    'Color', 'none', ...
    'XAxisLocation', 'bottom', ...
    'YAxisLocation', 'right', ...
    'YColor', 'none', ...
    'XColor', 'k', ...
    'Box', 'off', ...
    'HitTest', 'off', ...
    'HandleVisibility', 'off');

axTopX.XTick = hours_img_plot(idx);
axTopX.XTickLabel = imgLabels;
axTopX.TickLength = [0.004 0.004];
xlabel(axTopX, 'Image number');

% Hide normal x-axis of top plot
axTop.XTick = [];
axTop.XColor = 'none';

% Link overlay too
linkaxes([axTop axTopX axMid axBot], 'x');

% Force exact initial alignment
axTopX.Position = axTop.Position;
axTopX.XLim = axTop.XLim;

% Listener: whenever axTop position changes, update overlay axis
posListener = addlistener(axTop, 'Position', 'PostSet', ...
    @(~,~) set(axTopX, 'Position', axTop.Position));

% Listener: whenever x-limits change, update overlay axis
xlimListener = addlistener(axTop, 'XLim', 'PostSet', ...
    @(~,~) set(axTopX, 'XLim', axTop.XLim));

% Store listeners so MATLAB does not delete them
setappdata(gcf, 'TopAxisPositionListener', posListener);
setappdata(gcf, 'TopAxisXLimListener', xlimListener);

% Hide axle on top panel
axTop.XRuler.Axle.Visible = 'off';

% Keep overlay aligned after resizing
fig = gcf;
fig.SizeChangedFcn = @(~,~) updateTopOverlay(axTop, axTopX);

updateTopOverlay(axTop, axTopX);
drawnow
updateTopOverlay(axTop, axTopX);

%% -------------------------------------------------
% OPTIONAL: set independent y-limits
% Uncomment and adjust if needed
%% -------------------------------------------------
% ylim(axTop, [-20 20]);
% yyaxis(axMid,'left');  ylim(axMid, [0 1]);
% yyaxis(axMid,'right'); ylim(axMid, [0 10]);
% yyaxis(axBot,'left');  ylim(axBot, [-2 13]);
% yyaxis(axBot,'right'); ylim(axBot, [2 10]);

%% -------------------------------------------------
% Save figure
%% -------------------------------------------------
exportgraphics(gcf, fullfile(plotPath, 'combined_experiment_plot_3panels.pdf'), ...
    'Resolution', 300);

fprintf('Saved plot in:\n%s\n', plotPath);

%% -------------------------------------------------
% Helper function
%% -------------------------------------------------
function updateTopOverlay(axTop, axTopX)
    drawnow limitrate
    axTopX.Position = axTop.Position;
    axTopX.XLim = axTop.XLim;
end
