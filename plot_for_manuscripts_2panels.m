clear; clc; close all;
%% Two-panel square figure
%
% TOP PANEL (left y: biomass occupation %, right y: bulk DO mg/L)
% BOTTOM PANEL (left y: flowrate µL/min, right y: pressure gradient mbar)
%
% X-axis: experiment time in hours, t0 = earliest timestamp across all signals
% Vertical event lines: user-defined times + labels (edit eventTimes / eventLabels below)

%% -------------------------------------------------
% USER-DEFINED EVENT LINES
% Set elapsed-time positions (hours, same origin as t0) and labels.
% Lines appear as dashed verticals on both panels.
%% -------------------------------------------------
eventTimes  = []; % <-- edit: elapsed hours
eventLabels = {}; % <-- edit: one label per time
eventColor  = [0.0 0.0 0.0];   % dark charcoal
eventLW     = 1;

%% -------------------------------------------------
% Paths  (unchanged from original)
%% -------------------------------------------------
mainPath    = pwd;
cd(mainPath); cd('../');
projectPath = pwd;

cd(projectPath); cd('processed_data\pq_cleaned_data\');
pdCleanedPath = pwd;

cd(projectPath); cd('logs\');
logsPath = pwd;

cd(projectPath); cd('processed_data\biomass_occupation_bulkDO\');
bioDOPath = pwd;

cd(projectPath); cd('processed_data\plots\');
plotPath = pwd;

%% -------------------------------------------------
% File names  (unchanged)
%% -------------------------------------------------
flowrateFile = 'cleaned_flowrate.csv';
pressFile    = 'cleaned_pressures.csv';
timeFile     = 'imaging_timestamp.xlsx';

listing = dir(fullfile(bioDOPath, '*_main_results.mat'));
if isempty(listing)
    error('No matching *_main_results.mat file found in:\n%s', bioDOPath);
end
bioMatFile = listing(1).name;

%% -------------------------------------------------
% Load flowrate
%% -------------------------------------------------
TTq = readtable(fullfile(pdCleanedPath, flowrateFile), 'TextType', 'string');
TTq.datetime = datetime(TTq.datetime, 'InputFormat', 'MM/dd/yyyy hh:mm:ss a');
t_q      = TTq.datetime(:);
q_smooth = TTq.q_smooth(:);

%% -------------------------------------------------
% Load pressure
%% -------------------------------------------------
TTp = readtable(fullfile(pdCleanedPath, pressFile), 'TextType', 'string');
TTp.datetime = datetime(TTp.datetime, 'InputFormat', 'MM/dd/yyyy hh:mm:ss a');
t_p       = TTp.datetime(:);
dp_smooth = TTp.dP_smooth(:);

%% -------------------------------------------------
% Load imaging timestamps
%% -------------------------------------------------
imagingTime = readtable(fullfile(logsPath, timeFile), 'TextType', 'string');
t_img = datetime(imagingTime.Datetime, 'InputFormat', 'yyyy-MM-dd HH:mm:ss');
t_img = t_img(:);

%% -------------------------------------------------
% Load biomass occupation and bulk DO
%% -------------------------------------------------
S = load(fullfile(bioDOPath, bioMatFile));
biomass_occ     = S.data.biomass_occupation(:);
biomass_occ_std = S.data.biomass_occupation_std(:);
bulk_DO         = S.data.bulk_do(:);
bulk_DO_std     = S.data.bulk_do_std(:);

if length(biomass_occ) ~= length(t_img)
    error('Length of biomass_occ does not match imaging timestamps.');
end
if length(bulk_DO) ~= length(t_img)
    error('Length of bulk_DO does not match imaging timestamps.');
end

% DO may be entirely NaN if no DO data was available for this experiment
hasDO = any(~isnan(bulk_DO));
if ~hasDO
    warning('bulk_DO is all NaN — plotting biomass occupation only (no DO axis).');
end

%% -------------------------------------------------
% Common t0 — earliest timestamp across all signals
%% -------------------------------------------------
t0        = min([t_q; t_p; t_img]);
hours_q   = hours(t_q   - t0);
hours_p   = hours(t_p   - t0);
hours_img = hours(t_img - t0);

%% -------------------------------------------------
% Colors  (variable-based, colorblind-accessible)
%% -------------------------------------------------
clrBio = [0.483  0.619  0.243];   % olive   — biomass
clrDO  = [0.004  0.400  0.369];   % teal    — dissolved oxygen
clrQ   = [0.129  0.400  0.675];   % steel blue — flowrate
clrDP  = [0.698  0.094  0.169];   % crimson    — pressure

markerSz  = 0.1;
lineWMain_bottom = 1.5;
lineWMain_top = 3;
axisfontsize = 9;

%% -------------------------------------------------
% Figure: square canvas, white background
% Target export size: 560 × 560 pt  →  use 7" × 7" at 300 dpi
%% -------------------------------------------------
figW_in = 7;
figH_in = 5;
fig = figure('Color', 'w', ...
    'Units', 'inches', ...
    'Position', [1 1.1 figW_in figH_in]);

tl = tiledlayout(2, 1, ...
    'TileSpacing', 'compact', ...
    'Padding',     'compact');

%% =================================================
% TOP PANEL: Biomass occupation (left) + Bulk DO (right, if available)
%% =================================================
axTop = nexttile(tl, 1);
hold(axTop, 'on');

% ---- Left y-axis: biomass (no error bars, small filled circles) ----
if hasDO
    yyaxis(axTop, 'left');   % only need to switch axes if a right axis will exist
end
plot(axTop, hours_img, biomass_occ, '-o', ...
    'Color',           clrBio, ...
    'MarkerFaceColor', clrBio, ...
    'MarkerEdgeColor', clrBio, ...
    'MarkerSize',      markerSz, ...
    'LineWidth',       lineWMain_top);

ylabel(axTop, 'Biomass occupation (%)', ...
    'Color', clrBio, 'FontSize', axisfontsize, 'FontWeight', 'bold');
axTop.YColor = clrBio;
yMaxBio = max(biomass_occ) * 1.15 + eps;
ylim(axTop, [0  yMaxBio]);

% ---- Right y-axis: bulk DO (shaded ±1 std band, small square markers) ----
if hasDO
    yyaxis(axTop, 'right');

    % Shaded band first (drawn underneath the line)
    xFill = [hours_img(:); flipud(hours_img(:))];
    yFill = [bulk_DO(:) + bulk_DO_std(:); flipud(bulk_DO(:) - bulk_DO_std(:))];
    yFill = max(yFill, 0);   % clamp to zero (DO cannot be negative)
    hBand = fill(axTop, xFill, yFill, clrDO, ...
        'FaceAlpha', 0.15, ...
        'EdgeColor', 'none');
    hBand.Annotation.LegendInformation.IconDisplayStyle = 'off';

    % Line + small square markers on top
    plot(axTop, hours_img, bulk_DO, '-s', ...
        'Color',           clrDO, ...
        'MarkerFaceColor', clrDO, ...
        'MarkerEdgeColor', clrDO, ...
        'MarkerSize',      markerSz, ...
        'LineWidth',       lineWMain_top);

    ylabel(axTop, 'Bulk DO concentration (mg L^{-1})', ...
        'Color', clrDO, 'FontSize', axisfontsize, 'FontWeight', 'bold');
    axTop.YColor = clrDO;
    yMaxDO = max(bulk_DO + bulk_DO_std) * 1.15 + eps;
    ylim(axTop, [0  yMaxDO]);
end

% ---- Formatting ----
grid(axTop, 'on');
box(axTop, 'on');
axTop.XTickMode      = 'auto';   % keep ticks (preserves grid lines)
axTop.XTickLabel     = {};       % hide the numbers only
axTop.GridAlpha      = 0.15;
axTop.LineWidth      = 0.8;
axTop.FontWeight     = 'bold';   % bold tick numbers on both y-axes

%% =================================================
% BOTTOM PANEL: Flowrate (left) + Pressure (right)
%% =================================================
axBot = nexttile(tl, 2);
hold(axBot, 'on');

% ---- Left y-axis: flowrate ----
yyaxis(axBot, 'left');
plot(axBot, hours_q, q_smooth, '-', ...
    'Color',     clrQ, ...
    'LineWidth', lineWMain_bottom);

ylabel(axBot, 'Flowrate (\muL min^{-1})', ...
    'Color', clrQ, 'FontSize', axisfontsize, 'FontWeight', 'bold');
axBot.YColor = clrQ;
ylim(axBot, [-0.5  12.5]);
axBot.YTick      = 0:2:12;
axBot.YTickLabel = arrayfun(@num2str, 0:2:12, 'UniformOutput', false);

% Zero-flowrate reference line
hZeroQ = yline(axBot, 0, '--', 'Color', clrQ, 'LineWidth', 0.9, 'Alpha', 0.5);
hZeroQ.Annotation.LegendInformation.IconDisplayStyle = 'off';

% ---- Right y-axis: pressure ----
yyaxis(axBot, 'right');
plot(axBot, hours_p, dp_smooth, '-', ...
    'Color',     clrDP, ...
    'LineWidth', lineWMain_bottom);

ylabel(axBot, '\DeltaP (mbar)', ...
    'Color', clrDP, 'FontSize', axisfontsize, 'FontWeight', 'bold');
axBot.YColor = clrDP;
ylim(axBot, [0  max(dp_smooth)*1.15 + eps]);

xlabel(axBot, 'Experiment time (h)', 'FontSize', 11, 'FontWeight', 'bold');

% ---- Formatting ----
grid(axBot, 'on');
box(axBot, 'on');
axBot.GridAlpha  = 0.15;
axBot.LineWidth  = 0.8;
axBot.FontWeight = 'bold';   % bold tick numbers on both y-axes and x-axis

%% -------------------------------------------------
% Link x-axes and set common x-range
%% -------------------------------------------------
linkaxes([axTop axBot], 'x');
xMax_h = max([hours_q(:); hours_p(:); hours_img(:)]);
xlim(axTop, [0 xMax_h]);

%% -------------------------------------------------
% Vertical event lines on both panels
% Labels sit OUTSIDE the top panel, above it, like a top-axis tick label.
% Uses a transparent overlay axes pinned to axTop for reliable placement.
%% -------------------------------------------------
for ev = 1:length(eventTimes)
    et = eventTimes(ev);

    h1 = xline(axTop, et, '--', ...
        'Color', eventColor, 'LineWidth', eventLW, 'Alpha', 0.75);
    h1.Annotation.LegendInformation.IconDisplayStyle = 'off';

    h2 = xline(axBot, et, '--', ...
        'Color', eventColor, 'LineWidth', eventLW, 'Alpha', 0.75);
    h2.Annotation.LegendInformation.IconDisplayStyle = 'off';
end

% Force layout so axTop.Position is finalised before we read it
drawnow;

%% -------------------------------------------------
% Overlay axis above top panel for event labels
% XLim matches axTop so data coordinates map directly to label positions.
%% -------------------------------------------------
axEvt = axes('Units',           'normalized', ...
             'Position',        axTop.Position, ...
             'Color',           'none', ...
             'XLim',            axTop.XLim, ...
             'YLim',            [0 0.99], ...
             'XColor',          'none', ...
             'YColor',          'none', ...
             'Box',             'off', ...
             'HitTest',         'off', ...
             'HandleVisibility','off');

for ev = 1:length(eventTimes)
    text(axEvt, eventTimes(ev), 1, eventLabels{ev}, ...
        'Units',               'data', ...
        'Color',               eventColor, ...
        'FontSize',            10, ...
        'FontWeight',          'bold', ...
        'HorizontalAlignment', 'center', ...
        'VerticalAlignment',   'bottom', ...
        'Rotation',            0, ...
        'Interpreter',         'none', ...
        'Clipping',            'off');
end

% Keep overlay in sync if the figure is resized
lEvtPos = addlistener(axTop, 'Position', 'PostSet', ...
    @(~,~) set(axEvt, 'Position', axTop.Position, 'XLim', axTop.XLim));
lEvtLim = addlistener(axTop, 'XLim', 'PostSet', ...
    @(~,~) set(axEvt, 'XLim', axTop.XLim));
setappdata(fig, 'ListenerEvtPos', lEvtPos);
setappdata(fig, 'ListenerEvtLim', lEvtLim);

%% -------------------------------------------------
% Save as square PDF (vector) and TIF (raster, 300 dpi)
%% -------------------------------------------------
pdfOut = fullfile(plotPath, 'timeseries_2panel_square.pdf');
tifOut = fullfile(plotPath, 'timeseries_2panel_square.tif');

exportgraphics(fig, pdfOut, 'ContentType', 'vector');
exportgraphics(fig, tifOut, 'Resolution', 300);

fprintf('Saved:\n  %s\n  %s\n', pdfOut, tifOut);
