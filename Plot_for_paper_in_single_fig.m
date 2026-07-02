%% Single-panel PNAS timeseries figure
%
% LEFT  y-axis : hydraulic parameter
%                  flag_cP = true  → flowrate (µL/min),  blue
%                  flag_cP = false → ΔP (mbar),          red
%
% RIGHT y-axis : unified 0–100 % scale
%                  Biomass occupation (olive, solid line + shaded ±1σ)
%                  DO rescaled: 0 mg/L → 0 %, DO_MAX_MGPL mg/L → 100 %
%                              (teal, solid line + shaded ±1σ)
%                  DO is plotted only up to t_DO_end_h (hours)
%
% No legend — axis label colors identify each variable.
% Right ylabel: two-color text annotation (olive = biomass, teal = DO).
%
% Vertical event lines + labels above the panel.
% Export: 7" × 2.5"  PDF (vector) + TIF (300 dpi)  — PNAS single-column

clear; clc; close all;

%% =========================================================
%  USER SETTINGS  ← edit here
%% =========================================================

% --- Hydraulic flag ---
flag_cP = true;          % true  → plot flowrate on left axis (cP condition)
                         % false → plot ΔP      on left axis (cQ condition)

% --- DO truncation ---
t_DO_end_h = inf;         % DO line/fill drawn from t=0 up to this elapsed hour

% --- DO physical scale for right-axis normalisation ---
DO_MAX_MGPL = 8;         % 100 % on the right axis = this many mg/L

% --- Event lines ---
eventTimes  = [11.3]; %[8.5, 13.1, 22.0, 37.5];                              % <-- edit: elapsed hours
eventLabels = {'bioclogging'}; %{'a,e', 'b,f', 'c,g', 'd,h'}; % <-- edit: one label per time
eventColor  = [0.0 0.0 0.0];   % dark charcoal
eventLW     = 1;

% --- Axis-side assignment ---
% cP experiment: hydraulic (flowrate) on LEFT, biomass/DO on RIGHT
% cQ experiment: hydraulic (ΔP)       on RIGHT, biomass/DO on LEFT
if flag_cP
    hydraulicAxis = 'left';
    bioDOAxis     = 'right';
else
    hydraulicAxis = 'right';
    bioDOAxis     = 'left';
end

%% =========================================================
%  PATHS
%% =========================================================
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
 
%% =========================================================
%  FILE NAMES
%% =========================================================
flowrateFile = 'cleaned_flowrate.csv';
pressFile    = 'cleaned_pressures.csv';
timeFile     = 'imaging_timestamp.xlsx';
 
listing = dir(fullfile(bioDOPath, '*_main_results.mat'));
if isempty(listing)
    error('No matching *_main_results.mat file found in:\n%s', bioDOPath);
end
bioMatFile = listing(1).name;
 
%% =========================================================
%  LOAD DATA
%% =========================================================
 
TTq = readtable(fullfile(pdCleanedPath, flowrateFile), 'TextType', 'string');
TTq.datetime = datetime(TTq.datetime, 'InputFormat', 'MM/dd/yyyy hh:mm:ss a');
t_q      = TTq.datetime(:);
q_smooth = TTq.q_smooth(:);
 
TTp = readtable(fullfile(pdCleanedPath, pressFile), 'TextType', 'string');
TTp.datetime = datetime(TTp.datetime, 'InputFormat', 'MM/dd/yyyy hh:mm:ss a');
t_p       = TTp.datetime(:);
dp_smooth = TTp.dP_smooth(:);
 
imagingTime = readtable(fullfile(logsPath, timeFile), 'TextType', 'string');
t_img = datetime(imagingTime.Datetime, 'InputFormat', 'yyyy-MM-dd HH:mm:ss');
t_img = t_img(:);
 
S = load(fullfile(bioDOPath, bioMatFile));

biomass_occ     = S.data.biomass_occupation(:);
biomass_occ_std = S.data.biomass_occupation_std(:);

hasDO = isfield(S.data, 'bulk_do') && isfield(S.data, 'bulk_do_std');
if hasDO
    bulk_DO     = S.data.bulk_do(:);
    bulk_DO_std = S.data.bulk_do_std(:);
end

if length(biomass_occ) ~= length(t_img)
    error('Length of biomass_occ does not match imaging timestamps.');
end
if hasDO && length(bulk_DO) ~= length(t_img)
    error('Length of bulk_DO does not match imaging timestamps.');
end
 
%% =========================================================
%  TIME ALIGNMENT
%% =========================================================
t0        = min([t_q; t_p; t_img]);
hours_q   = hours(t_q   - t0);
hours_p   = hours(t_p   - t0);
hours_img = hours(t_img - t0);
 
%% =========================================================
%  DO RESCALING  (mg/L → %)
%% =========================================================
if hasDO
    DO_pct     = (bulk_DO     / DO_MAX_MGPL) * 100;
    DO_pct_std = (bulk_DO_std / DO_MAX_MGPL) * 100;

    mask_DO      = hours_img <= t_DO_end_h;
    hours_img_DO = hours_img(mask_DO);
    DO_pct_plot  = DO_pct(mask_DO);
    DO_std_plot  = DO_pct_std(mask_DO);
end
 
%% =========================================================
%  COLORS
%% =========================================================
clrBio = [0.483  0.619  0.243];   % olive       — biomass
clrDO  = [0.004  0.400  0.369];   % teal        — dissolved oxygen
clrQ   = [0.129  0.400  0.675];   % steel blue  — flowrate
clrDP  = [0.698  0.094  0.169];   % crimson     — pressure
 
%% =========================================================
%  FIGURE SETUP  — 7" × 2.5" PNAS single-column
%% =========================================================
figW_in = 8;
figH_in = 2.5;
 
fig = figure('Color', 'w', ...
    'Units',    'inches', ...
    'Position', [1  1  figW_in  figH_in]);
 
ax = axes(fig);
hold(ax, 'on');
 
%% =========================================================
%  LEFT Y-AXIS — hydraulic parameter
%% =========================================================
yyaxis(ax, hydraulicAxis);
 
if flag_cP
    hydraulicColor = clrQ;
    plot(ax, hours_q, q_smooth, '-', ...
        'Color', hydraulicColor, 'LineWidth', 1.5);
    ylabel(ax, 'Flowrate (\muL min^{-1})', ...
        'Color', hydraulicColor, 'FontSize', 10, 'FontWeight', 'bold');
    ax.YColor = hydraulicColor;
    ylim(ax, [-0.5  12.5]);
    ax.YTick      = 0:2:12;
    ax.YTickLabel = arrayfun(@num2str, 0:2:12, 'UniformOutput', false);
    hZ = yline(ax, 0, '--', 'Color', hydraulicColor, 'LineWidth', 0.9, 'Alpha', 0.5);
    hZ.Annotation.LegendInformation.IconDisplayStyle = 'off';
    biomass_occ_ant_loc = [0.994474206349205 0.0208333333333336 0.350051587301587 0.0972222222222222];
    bulk_do_ant_loc = [0.975128968253961 0.2075 0.225694444444444 0.0972222222222222];
else
    hydraulicColor = clrDP;
    plot(ax, hours_p, dp_smooth, '-', ...
        'Color', hydraulicColor, 'LineWidth', 1.5);
    ylabel(ax, '\DeltaP (mbar)', ...
        'Color', hydraulicColor, 'FontSize', 10, 'FontWeight', 'bold');
    ax.YColor = hydraulicColor;
    ylim(ax, [0  max(dp_smooth)*1.15 + eps]);
    biomass_occ_ant_loc = [0.0908283730158643 0.0208333333333336 0.350051587301585 0.0972222222222222];
    bulk_do_ant_loc = [0.07148313492062 0.2075 0.225694444444443 0.0972222222222222];
end
 
%% =========================================================
%  RIGHT Y-AXIS — Biomass (%) and DO (rescaled %)
%% =========================================================
yyaxis(ax, bioDOAxis);
 
% DO: shaded band first, then line (behind biomass)
if hasDO
    xFill_DO = [hours_img_DO(:); flipud(hours_img_DO(:))];
    yFill_DO = [DO_pct_plot(:) + DO_std_plot(:); ...
                flipud(DO_pct_plot(:) - DO_std_plot(:))];
    yFill_DO = max(yFill_DO, 0);
    hDOband = fill(ax, xFill_DO, yFill_DO, clrDO, ...
        'FaceAlpha', 0.15, 'EdgeColor', 'none');
    hDOband.Annotation.LegendInformation.IconDisplayStyle = 'off';

    plot(ax, hours_img_DO, DO_pct_plot, '-', ...
        'Color', clrDO, 'LineWidth', 2);
end

plot(ax, hours_img, biomass_occ, '-', ...
    'Color', clrBio, 'LineWidth', 2);

ylim(ax, [0  100]);
ax.YTick      = 0:20:100;
ax.YTickLabel = arrayfun(@(v) sprintf('%d%%', v), 0:20:100, 'UniformOutput', false);
ax.YColor     = [0.25 0.25 0.25];
ylabel(ax, '');                    % suppress default ylabel text
 
%% =========================================================
%  X-AXIS
%% =========================================================
xMax_h = max([hours_q(:); hours_p(:); hours_img(:)]);
xlim(ax, [0  xMax_h]);
xTicks = ax.XTick;
ax.XTick = xTicks(2:end);   % drop first and last auto tick
xlabel(ax, 'Experiment time (h)', 'FontSize', 10, 'FontWeight', 'bold');
 
%% =========================================================
%  NO LEGEND — axis colors identify variables
%% =========================================================
 
%% =========================================================
%  GRID + BOX
%% =========================================================
grid(ax, 'on');
box(ax, 'on');
ax.GridAlpha  = 0.15;
ax.LineWidth  = 0.8;
ax.FontSize   = 9;
ax.FontWeight = 'bold';
 
%% =========================================================
%  VERTICAL EVENT LINES
%% =========================================================
for ev = 1:length(eventTimes)
    h1 = xline(ax, eventTimes(ev), '--', ...
        'Color', eventColor, 'LineWidth', eventLW, 'Alpha', 0.75);
    h1.Annotation.LegendInformation.IconDisplayStyle = 'off';
end
 
% Force layout so positions are finalised
drawnow;
 
%% =========================================================
%  TWO-COLOR RIGHT YLABEL via annotation('textbox')
%  annotation() works in figure-normalized units and supports rotation.
%  Each label is a zero-size textbox centred on the right spine.
%  Line 1 (top):    "Biomass occ. (%)"      — olive
%  Line 2 (bottom): "DO (%, 100% = X mg/L)" — teal
%% =========================================================
 
% Positions calibrated from MATLAB auto-generated figure code (29-Jun-2026).
% If you change figW_in / figH_in or margins, re-run the figure tool to update them.
 
% DO (teal) — position from auto-generated code
doLabel = sprintf('Bulk DO concentration', DO_MAX_MGPL);
annotation(fig, 'textbox', ...
    bulk_do_ant_loc, ...
    'String',              doLabel, ...
    'Color',               clrDO, ...
    'FontSize',            9, ...
    'FontWeight',          'bold', ...
    'HorizontalAlignment', 'center', ...
    'VerticalAlignment',   'middle', ...
    'Rotation',            90, ...
    'EdgeColor',           'none', ...
    'BackgroundColor',     'none', ...
    'Interpreter',         'none');
 
% Biomass (olive) — position from auto-generated code
annotation(fig, 'textbox', ...
    biomass_occ_ant_loc, ...
    'String',              'Biomass occupation', ...
    'Color',               clrBio, ...
    'FontSize',            9, ...
    'FontWeight',          'bold', ...
    'HorizontalAlignment', 'center', ...
    'VerticalAlignment',   'middle', ...
    'Rotation',            90, ...
    'EdgeColor',           'none', ...
    'BackgroundColor',     'none', ...
    'Interpreter',         'none');
 
%% =========================================================
%  OVERLAY AXIS FOR EVENT LABELS (above panel)
%% =========================================================
axEvt = axes('Units',            'normalized', ...
             'Position',         ax.Position, ...
             'Color',            'none', ...
             'XLim',             ax.XLim, ...
             'YLim',             [0  0.99], ...
             'XColor',           'none', ...
             'YColor',           'none', ...
             'Box',              'off', ...
             'HitTest',          'off', ...
             'HandleVisibility', 'off');
 
for ev = 1:length(eventTimes)
    text(axEvt, eventTimes(ev), 1, eventLabels{ev}, ...
        'Units',               'data', ...
        'Color',               eventColor, ...
        'FontSize',            9, ...
        'FontWeight',          'bold', ...
        'HorizontalAlignment', 'center', ...
        'VerticalAlignment',   'bottom', ...
        'Rotation',            0, ...
        'Interpreter',         'none', ...
        'Clipping',            'off');
end
 
lPos = addlistener(ax, 'Position', 'PostSet', ...
    @(~,~) set(axEvt, 'Position', ax.Position, 'XLim', ax.XLim));
lLim = addlistener(ax, 'XLim', 'PostSet', ...
    @(~,~) set(axEvt, 'XLim', ax.XLim));
setappdata(fig, 'ListenerEvtPos', lPos);
setappdata(fig, 'ListenerEvtLim', lLim);
 
%% =========================================================
%  EXPORT  — 7" × 2.5", PDF vector + TIF 300 dpi
%% =========================================================
fig.Units    = 'inches';
fig.Position = [1  1  figW_in  figH_in];
 
pdfOut = fullfile(plotPath, 'timeseries_1panel_PNAS.pdf');
tifOut = fullfile(plotPath, 'timeseries_1panel_PNAS.tif');
 
exportgraphics(fig, pdfOut, 'ContentType', 'vector');
exportgraphics(fig, tifOut, 'Resolution', 300);
 
fprintf('Saved:\n  %s\n  %s\n', pdfOut, tifOut);
